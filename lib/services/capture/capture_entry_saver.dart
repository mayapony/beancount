library;

import '../../data/db/app_database.dart';
import '../../data/db/enums.dart';
import '../../data/repositories/account_repository.dart';
import '../../data/repositories/app_state_repository.dart';
import '../../data/repositories/attachment_repository.dart';
import '../../data/repositories/category_repository.dart';
import '../../data/repositories/transaction_repository.dart';
import '../entry/entry_writer.dart';
import 'capture_candidate.dart';

/// 把一条捕获候选落成交易。
///
/// 候选只有金额 + 方向 + 备注，没有分类 / 账户，这里按方向兜底：
/// 分类用「上次用的 → 其他 → 该方向第一个」，账户用上次用的（可选）。
/// 退款没有独立账本类型，映射为收入（钱回来），备注保留原文让用户在列表核对。
class CaptureEntrySaver {
  CaptureEntrySaver({required this.db, AttachmentRepository? attachments})
      : _attachments = attachments ?? AttachmentRepository(db);

  final AppDatabase db;
  final AttachmentRepository _attachments;

  Future<CreateResult> save(CaptureCandidate candidate, {required DateTime now}) async {
    final amount = candidate.amountCents;
    if (amount == null || amount <= 0) {
      throw StateError('没有可用的金额');
    }

    final type = candidate.direction == CaptureDirection.expense
        ? EntryType.expense
        : EntryType.income;
    final category = await _defaultCategory(candidate.direction);
    final account = await _defaultAccount();

    final writer = EntryWriter(
      transactions: TransactionRepository(db, attachments: _attachments),
      attachments: _attachments,
    );
    return writer.submit(
      type: type,
      amountCents: amount,
      happenedAt: candidate.happenedAt ?? now,
      categoryId: category.id,
      accountId: account?.id,
      note: (candidate.note ?? '').trim(),
      source: EntrySource.auto,
    );
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
