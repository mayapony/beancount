import 'dart:typed_data';

import '../../data/db/app_database.dart';
import '../../data/db/enums.dart';
import '../../data/repositories/account_repository.dart';
import '../../data/repositories/app_state_repository.dart';
import '../../data/repositories/attachment_repository.dart';
import '../../data/repositories/category_repository.dart';
import '../../data/repositories/transaction_repository.dart';
import '../attachments/image_picker_service.dart';
import '../capture/capture_account_map.dart';
import '../ocr/auto_create_policy.dart';
import '../entry/entry_writer.dart';
import '../ocr/entry_matching.dart';
import '../ocr/receipt_guess.dart';

/// 自动记账的结果：插入成功，或命中同一条去重键。
class AutoScreenshotSave {
  const AutoScreenshotSave({
    required this.inserted,
    required this.amountCents,
    required this.categoryName,
    this.accountName,
  });

  final bool inserted;
  final int amountCents;
  final String categoryName;
  final String? accountName;

  bool get duplicate => !inserted;
}

/// 把后台识别结果直接落成一笔支出，不再要求用户打开面板确认。
///
/// 只处理「识别出了金额」的情况；字段缺失时的兜底：
/// 分类用匹配到的 → 上次用的 → 「其他」→ 第一个支出分类；
/// 账户用匹配到的 → 上次用的 → 不选账户。
/// 图片随交易一起落盘；命中去重时不会留下孤儿附件。
class AutoScreenshotSaver {
  AutoScreenshotSaver({
    required this.db,
    AttachmentRepository? attachments,
    this.autoCreateCategories = false,
    AutoCreatePolicy? autoCreatePolicy,
  })  : _attachments = attachments ?? AttachmentRepository(db),
        _autoCreatePolicy = autoCreatePolicy ?? AutoCreatePolicy(AppStateRepository(db));

  final AppDatabase db;
  final AttachmentRepository _attachments;

  /// 用户的「自动新建分类」开关；关闭时一律不新建，退回既有兜底。
  final bool autoCreateCategories;

  final AutoCreatePolicy _autoCreatePolicy;

  Future<AutoScreenshotSave> save({
    required ReceiptGuess guess,
    required Uint8List imageBytes,
    required String fileName,
    required bool autoTags,
    required DateTime now,
    String? sourcePackage,
  }) async {
    final amount = guess.amountCents;
    if (amount == null || amount <= 0) {
      throw StateError('没有可用的金额');
    }

    final categoryRepo = CategoryRepository(db);
    final expenseCategories = await categoryRepo.all(CategoryType.expense);
    if (expenseCategories.isEmpty) {
      throw StateError('没有可用的支出分类');
    }

    final state = AppStateRepository(db);
    final selection = await state.lastSelection();
    var category = matchCategory(
      guess.categoryName,
      expenseCategories,
      CategoryType.expense,
    );
    category ??= await _createRecognizedCategory(
      guess.categoryName,
      expenseCategories,
    );
    category ??= _categoryById(expenseCategories, selection.categoryId);
    category ??= _categoryByName(expenseCategories, '其他');
    category ??= expenseCategories.first;

    final accounts = await AccountRepository(db).all();
    final channel = guess.accountName?.trim();
    final accountMap = CaptureAccountMap(state);
    Account? account = matchAccount(channel, accounts);

    // 模型给的是渠道泛称（银行卡 / 零钱 / 花呗），账本里是具体账户，
    // 字面上永远对不上。三级处理：同名 → 记住的映射 → 待人工确认。
    var needsReview = false;
    if (account == null && channel != null && channel.isNotEmpty) {
      final rememberedId = await accountMap.lookup(sourcePackage ?? '', channel);
      account = _accountById(accounts, rememberedId);
      needsReview = account == null;
    }
    // 模型没给渠道、也没记住过映射：沿用上次用的账户（老行为，不打扰用户）。
    account ??= needsReview ? null : _accountById(accounts, selection.accountId);

    final writer = EntryWriter(
      transactions: TransactionRepository(db, attachments: _attachments),
      attachments: _attachments,
    );
    final result = await writer.submit(
      type: EntryType.expense,
      amountCents: amount,
      happenedAt: guess.happenedAt ?? now,
      categoryId: category.id,
      accountId: account?.id,
      note: (guess.note ?? '').trim(),
      tags: autoTags ? guess.tagNames : const <String>[],
      images: [PickedImage(bytes: imageBytes, fileName: fileName)],
      // 截图入账也是自动入账：标记来源，才进得了「最近自动记账」审计列表。
      source: EntrySource.auto,
      sourcePackage: sourcePackage,
      sourceChannel: channel,
      needsReview: needsReview,
    );

    return AutoScreenshotSave(
      inserted: result.inserted,
      amountCents: amount,
      categoryName: category.name,
      accountName: account?.name,
    );
  }

  /// 识别出的分类账本里没有时，按「自动新建分类」开关与配额决定要不要建。
  ///
  /// 开关关闭、配额用尽、或者模型压根没给分类名，都返回 null，由调用方退回
  /// 「上次用的 →「其他」」的老兜底。
  Future<Category?> _createRecognizedCategory(
    String? name,
    List<Category> existing,
  ) async {
    final trimmed = name?.trim() ?? '';
    if (trimmed.isEmpty) return null;
    if (!autoCreateCategories) return null;
    final decision = await _autoCreatePolicy.checkCategory(
      enabled: true,
      categoryTotal: existing.length + 1,
    );
    if (!decision.allowed) return null;
    final created = await CategoryRepository(db).ensure(
      name: trimmed,
      type: CategoryType.expense,
    );
    await _autoCreatePolicy.markCategoryCreated();
    return created;
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
