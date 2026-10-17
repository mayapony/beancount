import 'dart:async';

import 'package:flutter/material.dart';

import '../data/db/app_database.dart';
import '../data/db/connection.dart';
import '../data/db/enums.dart';
import '../data/repositories/account_repository.dart';
import '../data/repositories/app_state_repository.dart';
import '../data/repositories/attachment_repository.dart';
import '../data/repositories/category_repository.dart';
import '../data/repositories/insights_repository.dart';
import '../data/repositories/transaction_repository.dart';
import '../services/import/import_service.dart';
import '../theme/tokens.dart';
import '../widgets/bean_bottom_nav.dart';
import '../widgets/bean_fab.dart';
import '../widgets/quick_entry_sheet.dart';
import 'assets_page.dart';
import 'insights_page.dart';
import 'settings_page.dart';
import 'transactions_page.dart';

class ShellPage extends StatefulWidget {
  const ShellPage({
    super.key,
    this.database,
    this.attachmentRepository,
  });

  /// 单测 / 截图脚本可以注入内存库；App 正常启动时为 null，走文件库。
  final AppDatabase? database;

  /// 附件仓储同样可注入（截图脚本需要把图片落到临时目录）。
  final AttachmentRepository? attachmentRepository;

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
  late final TransactionRepository _transactionRepo = TransactionRepository(_db);
  late final InsightsRepository _insightsRepo = InsightsRepository(_db);
  late final AttachmentRepository _attachmentRepo =
      widget.attachmentRepository ?? AttachmentRepository(_db);
  late final ImportService _importService = ImportService(
    db: _db,
    categories: _categoryRepo,
    accounts: _accountRepo,
    transactions: _transactionRepo,
    attachments: _attachmentRepo,
  );

  late final List<Widget> _pages = [
    TransactionsPage(
      repository: _transactionRepo,
      attachments: _attachmentRepo,
    ),
    InsightsPage(repository: _insightsRepo),
    AssetsPage(repository: _accountRepo),
    SettingsPage(importer: _importService),
  ];

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

    final palette = BeanPalette.of(context);
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
        initialCategoryId: _lastSelection.categoryId,
        initialIsIncome: _lastSelection.isIncome,
        initialAccountId: _lastSelection.accountId,
        onSubmit: (draft) async {
          try {
            final result = await _transactionRepo.create(
              NewTransaction(
                type: draft.isIncome ? EntryType.income : EntryType.expense,
                // 金额在面板里是两位小数字符串算出来的 double，这里一次换算成整数分
                amountCents: (draft.amount * 100).round(),
                categoryId: draft.category.id,
                accountId: draft.account?.id,
                happenedAt: draft.time,
                note: draft.note,
                tags: draft.tags,
              ),
            );
            if (!result.inserted) {
              return '这笔已经记过了（同一秒、同一金额、同一备注）';
            }
          } catch (_) {
            return '保存失败，请重试';
          }

          final selection = LastEntrySelection(
            categoryId: draft.category.id,
            accountId: draft.account?.id,
            isIncome: draft.isIncome,
          );
          setState(() => _lastSelection = selection);
          unawaited(_appState.saveSelection(selection));
          return null;
        },
      ),
    );
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
