library;

import '../../data/db/app_database.dart';
import '../../data/db/enums.dart';
import '../../data/repositories/account_repository.dart';
import '../../data/repositories/app_state_repository.dart';
import '../../data/repositories/attachment_repository.dart';
import '../../data/repositories/category_repository.dart';
import '../../data/repositories/transaction_repository.dart';
import '../../data/category_library.dart';
import '../entry/entry_writer.dart';
import '../ocr/auto_create_policy.dart';
import '../screenshot/screenshot_settings.dart';
import 'capture_candidate.dart';

/// 一次自动入账的结果：除了是否新增，还带上最终落到的分类与账户，供运行记录
/// 直接显示「这笔记到哪了」。
class CaptureSaveResult {
  const CaptureSaveResult({
    required this.inserted,
    required this.transactionId,
    required this.categoryName,
    required this.accountName,
  });

  final bool inserted;
  final String transactionId;
  final String categoryName;
  final String? accountName;
}

/// 把一条捕获候选落成交易。
///
/// 候选只有金额 + 方向 + 备注，没有分类 / 账户，这里按方向兜底：
/// 分类用「上次用的 → 其他 → 该方向第一个」，账户用上次用的（可选）。
/// 退款没有独立账本类型，映射为收入（钱回来），备注保留原文让用户在列表核对。
class CaptureEntrySaver {
  CaptureEntrySaver({
    required this.db,
    AttachmentRepository? attachments,
    this.autoCreateCategories,
  }) : _attachments = attachments ?? AttachmentRepository(db);

  /// 测试可覆盖；为空时读用户的「自动新建分类」开关。
  final bool? autoCreateCategories;

  final AppDatabase db;
  final AttachmentRepository _attachments;

  Future<CaptureSaveResult> save(CaptureCandidate candidate, {required DateTime now}) async {
    final amount = candidate.amountCents;
    if (amount == null || amount <= 0) {
      throw StateError('没有可用的金额');
    }

    final type = candidate.direction == CaptureDirection.expense
        ? EntryType.expense
        : EntryType.income;
    final category = await _categoryFor(candidate);
    final account = await _defaultAccount();

    final writer = EntryWriter(
      transactions: TransactionRepository(db, attachments: _attachments),
      attachments: _attachments,
    );
    final result = await writer.submit(
      type: type,
      amountCents: amount,
      happenedAt: candidate.happenedAt ?? now,
      categoryId: category.id,
      accountId: account?.id,
      note: (candidate.note ?? '').trim(),
      source: EntrySource.auto,
      sourcePackage: candidate.packageName,
    );
    return CaptureSaveResult(
      inserted: result.inserted,
      transactionId: result.transactionId,
      categoryName: category.name,
      accountName: account?.name,
    );
  }

  /// 先按捕获到的文本推分类，推不出来才走「上次用的 → 其他」。
  ///
  /// 通知/无障碍拿到的文本里常带商户名（「滴滴出行」「美团外卖」「星巴克」），
  /// 之前一律落「其他」，用户只能事后手改。
  Future<Category> _categoryFor(CaptureCandidate candidate) async {
    final inferred = await _categoryFromText(candidate);
    if (inferred != null) return inferred;
    return _defaultCategory(candidate.direction);
  }

  Future<Category?> _categoryFromText(CaptureCandidate candidate) async {
    final type = candidate.direction == CaptureDirection.expense
        ? CategoryType.expense
        : CategoryType.income;
    final text = '${candidate.note ?? ''} ${candidate.rawText ?? ''}';
    if (text.trim().isEmpty) return null;
    final categories = await CategoryRepository(db).all(type);

    // 1) 账本里已有的分类名直接出现在文本里
    for (final category in categories) {
      final name = category.name.trim();
      if (name.length >= 2 && text.contains(name)) return category;
    }

    // 2) 分类库的别名命中：先看账本里有没有同义分类，没有才考虑新建
    final hits = libraryEntriesInText(text, type: type);
    if (hits.isEmpty) return null;
    final hit = hits.first;
    final ledgerMatch = _matchExisting(categories, hit);
    if (ledgerMatch != null) return ledgerMatch;

    final enabled = autoCreateCategories ??
        (await ScreenshotSettingsStore(AppStateRepository(db))
                .load())
            .autoCreateCategories;
    if (!enabled) return null;
    final policy = AutoCreatePolicy(AppStateRepository(db));
    final decision = await policy.checkCategory(
      enabled: true,
      categoryTotal: categories.length + 1,
    );
    if (!decision.allowed) return null;
    final created = await CategoryRepository(db).ensure(
      name: hit.category.name,
      type: type,
    );
    await policy.markCategoryCreated();
    return created;
  }

  /// 库里命中的名字，账本里可能叫得更简（「出行交通」vs「交通」），尽量复用旧的。
  Category? _matchExisting(List<Category> categories, LibraryEntry hit) {
    final wanted = [hit.category.name, if (hit.parent != null) hit.parent!.name];
    for (final category in categories) {
      for (final name in wanted) {
        if (category.name == name) return category;
        if (category.name.length >= 2 &&
            (name.contains(category.name) || category.name.contains(name))) {
          return category;
        }
      }
    }
    return null;
  }

  Future<Category> _defaultCategory(CaptureDirection direction) async {
    final type = direction == CaptureDirection.expense
        ? CategoryType.expense
        : CategoryType.income;
    final categories = await CategoryRepository(db).all(type);
    if (categories.isEmpty) {
      throw StateError('没有可用的${type == CategoryType.expense ? '支出' : '收入'}分类');
    }

    final selection = await AppStateRepository(db).lastSelection();
    final byId = _categoryById(categories, selection.categoryId);
    if (byId != null) return byId;
    final other = _categoryByName(categories, '其他');
    return other ?? categories.first;
  }

  Future<Account?> _defaultAccount() async {
    final accounts = await AccountRepository(db).all();
    final selection = await AppStateRepository(db).lastSelection();
    return _accountById(accounts, selection.accountId);
  }

  static Category? _categoryById(List<Category> categories, String? id) {
    if (id == null) return null;
    for (final category in categories) {
      if (category.id == id) return category;
    }
    return null;
  }

  static Category? _categoryByName(List<Category> categories, String name) {
    for (final category in categories) {
      if (category.name == name) return category;
    }
    return null;
  }

  static Account? _accountById(List<Account> accounts, String? id) {
    if (id == null) return null;
    for (final account in accounts) {
      if (account.id == id) return account;
    }
    return null;
  }
}
