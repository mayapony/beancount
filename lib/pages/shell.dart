import 'dart:async';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

import '../data/db/app_database.dart';
import '../data/db/connection.dart';
import '../data/db/enums.dart';
import '../data/repositories/account_repository.dart';
import '../data/repositories/app_state_repository.dart';
import '../data/repositories/attachment_repository.dart';
import '../data/repositories/category_repository.dart';
import '../data/repositories/insights_repository.dart';
import '../data/repositories/lock_repository.dart';
import '../data/repositories/net_worth_repository.dart';
import '../data/repositories/recurring_repository.dart';
import '../data/repositories/transaction_repository.dart';
import '../services/export/export_service.dart';
import '../services/import/import_service.dart';
import '../services/ocr/receipt_recognizer.dart';
import '../services/ocr/receipt_recognizer_factory.dart';
import '../services/ocr/receipt_vision_settings.dart';
import '../services/attachments/image_picker_service.dart';
import '../services/entry/entry_writer.dart';
import '../services/recurring/recurring_service.dart';
import '../services/update/update_controller.dart';
import '../theme/theme_controller.dart';
import '../theme/tokens.dart';
import '../widgets/bean_bottom_nav.dart';
import '../widgets/bean_fab.dart';
import '../widgets/quick_entry_sheet.dart';
import '../widgets/update_prompt_sheet.dart';
import 'assets_page.dart';
import 'insights_page.dart';
import 'settings_page.dart';
import 'transactions_page.dart';

class ShellPage extends StatefulWidget {
  const ShellPage({
    super.key,
    this.database,
    this.attachmentRepository,
    this.themeController,
    this.visionKeys,
    this.updateController,
  });

  /// 单测 / 截图脚本可以注入内存库；App 正常启动时为 null，走文件库。
  final AppDatabase? database;

  /// 主题控制器（main 注入）；为空时设置页的主题行不可点。
  final ThemeController? themeController;

  /// 附件仓储同样可注入（截图脚本需要把图片落到临时目录）。
  final AttachmentRepository? attachmentRepository;

  /// API Key 存储：单测 / 截图脚本注入内存实现，避开平台通道。
  final ReceiptApiKeyStore? visionKeys;

  /// 更新控制器；为空时（Web/iOS/测试）不联网检查。
  final UpdateController? updateController;

  @override
  State<ShellPage> createState() => _ShellPageState();
}

class _ShellPageState extends State<ShellPage> {
  int _index = 0;

  late final AppDatabase _db =
      widget.database ?? AppDatabase(openDatabaseConnection());
  late final CategoryRepository _categoryRepo = CategoryRepository(_db);
  late final AccountRepository _accountRepo = AccountRepository(_db);
  late final AppStateRepository _appState = AppStateRepository(_db);
  late final TransactionRepository _transactionRepo =
      TransactionRepository(_db, attachments: _attachmentRepo);
  late final InsightsRepository _insightsRepo = InsightsRepository(_db);
  late final RecurringRepository _recurringRepo = RecurringRepository(_db);
  late final NetWorthRepository _netWorthRepo = NetWorthRepository(_db);
  late final LockRepository _lockRepo = LockRepository(_db);
  late final ReceiptVisionSettingsStore _visionSettings =
      ReceiptVisionSettingsStore(_appState);
  late final ReceiptApiKeyStore _visionKeys =
      widget.visionKeys ?? SecureReceiptApiKeyStore();
  late final EntryWriter _entryWriter = EntryWriter(
    transactions: _transactionRepo,
    attachments: _attachmentRepo,
  );
  late final AttachmentRepository _attachmentRepo =
      widget.attachmentRepository ?? AttachmentRepository(_db);
  late final ImportService _importService = ImportService(
    db: _db,
    categories: _categoryRepo,
    accounts: _accountRepo,
    transactions: _transactionRepo,
    attachments: _attachmentRepo,
  );
  late final ExportService _exportService = ExportService(
    transactions: _transactionRepo,
    attachments: _attachmentRepo,
  );

  late final List<Widget> _pages = [
    TransactionsPage(
      repository: _transactionRepo,
      attachments: _attachmentRepo,
      categories: _categoryRepo,
      accounts: _accountRepo,
    ),
    InsightsPage(
      repository: _insightsRepo,
      transactions: _transactionRepo,
      attachments: _attachmentRepo,
      categories: _categories,
    ),
    AssetsPage(repository: _accountRepo, netWorth: _netWorthRepo),
    SettingsPage(
      theme: widget.themeController,
      importer: _importService,
      exporter: _exportService,
      categories: _categoryRepo,
      accounts: _accountRepo,
      recurring: _recurringRepo,
      lock: _lockRepo,
      visionSettings: _visionSettings,
      visionKeys: _visionKeys,
      updateController: widget.updateController,
    ),
  ];

  /// 各币种上次用过的汇率（ppm），面板打开前从 app_state 读出来。
  Map<String, int> _fxRates = const <String, int>{};

  static const _fxCodes = ['USD', 'EUR', 'JPY', 'HKD', 'GBP', 'THB'];

  Future<void> _loadFxRates() async {
    final rates = <String, int>{};
    for (final code in _fxCodes) {
      final raw = await _appState.read('fx_$code');
      final ppm = int.tryParse(raw ?? '');
      if (ppm != null && ppm > 0) rates[code] = ppm;
    }
    if (!mounted) return;
    setState(() => _fxRates = rates);
  }

  Future<void> _rememberRate(String currency, int ppm) async {
    await _appState.write('fx_$currency', '$ppm');
    if (!mounted) return;
    setState(() {
      _fxRates = {..._fxRates, currency: ppm};
    });
  }

  /// 分类与账户是数据，面板打开前刷新一次（导入后可能新增）。
  List<Category> _categories = const <Category>[];
  List<AccountBalance> _accounts = const <AccountBalance>[];

  /// 上次记账的分类/类型/账户：下次打开面板直接继承（DESIGN.md §9.1）。
  /// 落在 `app_state` 表里，App 重启后仍然有效。
  LastEntrySelection _lastSelection = const LastEntrySelection();

  @override
  void initState() {
    super.initState();
    _loadInitialData();
    _loadFxRates();
    _runRecurringCatchUp();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_runUpdateCheck());
    });
  }

  /// 解锁进入主界面后检查更新：失败静默，发现新版本才弹提示。
  Future<void> _runUpdateCheck() async {
    final controller = widget.updateController;
    if (controller == null) return;
    try {
      await controller.initialize();
      if (!mounted) return;

      final updatedTo = controller.takeUpdatedTo();
      if (updatedTo != null) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(
            SnackBar(content: Text('已更新到 v$updatedTo')),
          );
      }

      final release = await controller.autoCheck();
      if (!mounted || release == null) return;
      await showUpdatePrompt(context, controller);
    } catch (_) {
      // 更新检查失败不能影响记账主流程。
    }
  }

  /// 打开 App 时补记到期的循环规则：不阻塞首帧，失败不影响使用。
  Future<void> _runRecurringCatchUp() async {
    try {
      final service = RecurringService(
        rules: _recurringRepo,
        transactions: _transactionRepo,
      );
      final result = await service.applyDue();
      if (result.created > 0) {
        debugPrint('循环记账补记 ${result.created} 笔（跳过 ${result.skipped} 期）');
      }
    } catch (error) {
      debugPrint('循环记账补记失败：$error');
    }
  }

  @override
  void dispose() {
    // 只关闭自己创建的库，注入的库由调用方负责
    if (widget.database == null) _db.close();
    super.dispose();
  }

  Future<void> _loadInitialData() async {
    final categories = await _categoryRepo.allCategories();
    final accounts = await _accountRepo.withBalances();
    final selection = await _appState.lastSelection();
    if (!mounted) return;
    setState(() {
      _categories = categories;
      _accounts = accounts;
      _lastSelection = selection;
    });
  }

  Future<void> _refreshChoices() async {
    final categories = await _categoryRepo.allCategories();
    final accounts = await _accountRepo.withBalances();
    if (!mounted) return;
    setState(() {
      _categories = categories;
      _accounts = accounts;
    });
  }

  /// 金豆按下 → 一次点击直接进入金额输入（不再有多级菜单）。
  Future<void> _openQuickEntry() async {
    await _refreshChoices();
    if (!mounted) return;
    // 最近备注：给备注弹窗做一键填充（查不到就空着，不影响记账）
    final recentNotes = await _transactionRepo.recentNotes();
    if (!mounted) return;
    // 每次打开都重读配置：设置里刚改完，下一次记账立即生效
    final recognizer = await systemReceiptRecognizer(
      settings: _visionSettings,
      keys: _visionKeys,
    );
    if (!mounted) return;

    final palette = BeanPalette.of(context);
    try {
      await showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        // 拖拽条由面板自己画（暖灰），不用 Material 默认的冷灰
        showDragHandle: false,
        backgroundColor: palette.surface,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
        builder: (_) => QuickEntrySheet(
          categories: _categories,
          accounts: _accounts,
          recentNotes: recentNotes,
          fxRates: _fxRates,
          pickImage: kIsWeb ? null : systemImagePicker(),
          recognizeReceipt: recognizer == null
              ? null
              : (bytes) => recognizeReceipt(recognizer, bytes),
          recognitionUnavailableHint:
              kIsWeb ? null : '视觉识别未开启，可在设置里配置 API Key',
          pickEnabled: !kIsWeb,
          initialCategoryId: _lastSelection.categoryId,
          initialIsIncome: _lastSelection.isIncome,
          initialAccountId: _lastSelection.accountId,
          onSubmit: (draft) async {
          try {
            final result = await _entryWriter.submit(
              type: draft.isTransfer
                  ? EntryType.transfer
                  : (draft.isIncome ? EntryType.income : EntryType.expense),
              // 金额在面板里是两位小数字符串算出来的 double，这里一次换算成整数分
              amountCents: (draft.amount * 100).round(),
              categoryId: draft.isTransfer ? null : draft.category?.id,
              accountId: draft.account?.id,
              toAccountId: draft.isTransfer ? draft.toAccount?.id : null,
              happenedAt: draft.time,
              note: draft.note,
              tags: draft.tags,
              images: draft.images,
              currency: draft.currency,
              originalAmountCents:
                  draft.currency == 'CNY' ? null : (draft.amount * 100).round(),
              ratePpm: draft.ratePpm,
            );
            if (!result.inserted) {
              return '这笔已经记过了（同一秒、同一金额、同一备注）';
            }
          } catch (_) {
            return '保存失败，请重试';
          }

          // 外币：记住这次用的汇率，下次记同币种时默认用它
          if (draft.currency != 'CNY' && draft.ratePpm != null) {
            unawaited(_rememberRate(draft.currency, draft.ratePpm!));
          }

          // 转账不参与「上次选择」的记忆（它的分类为空）
          if (!draft.isTransfer) {
            final selection = LastEntrySelection(
              categoryId: draft.category?.id,
              accountId: draft.account?.id,
              isIncome: draft.isIncome,
            );
            setState(() => _lastSelection = selection);
            unawaited(_appState.saveSelection(selection));
          }
          return null;
        },
      ),
    );
    } finally {
      // 识别器持有 HTTP 客户端：面板关了就不再留着连接
      await recognizer?.close();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          IndexedStack(index: _index, children: _pages),
          // 金豆的上半圆画在底栏盒子之外（Clip.none），而 Stack 只对盒内区域做
          // 命中测试——那半圈会出现"看得见、点不动"。这里补一块同尺寸的透明热区，
          // 让视觉与可点区域对齐（下半圆由底栏里的 BeanFab 自己接收）。
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: Center(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: _openQuickEntry,
                child: const SizedBox(
                  width: BeanFab.size,
                  height: BeanFab.size / 2,
                ),
              ),
            ),
          ),
        ],
      ),
      // 金豆由底栏自己绘制（见 BeanBottomNav）：Scaffold 的 FAB 会被底栏盖住投影
      bottomNavigationBar: BeanBottomNav(
        index: _index,
        onTap: (i) => setState(() => _index = i),
        onFabTap: _openQuickEntry,
      ),
    );
  }
}