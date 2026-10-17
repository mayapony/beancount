import 'package:drift/drift.dart';

import '../db/app_database.dart';
import '../db/enums.dart';

/// 账户 + 由交易推导出来的余额。
class AccountBalance {
  const AccountBalance({
    required this.account,
    required this.expenseCents,
    required this.incomeCents,
    this.count = 0,
  });

  final Account account;
  final int expenseCents;
  final int incomeCents;

  /// 关联的交易笔数（展示用）。
  final int count;

  /// 余额 = 初始余额 + 收入 − 支出。**不单独存**，永远不会漂移。
  int get balanceCents => account.initialBalanceCents + incomeCents - expenseCents;
}

/// 账户仓储：余额一律现算，账户本身只是"名字 + 初始余额"。
class AccountRepository {
  AccountRepository(this._db);

  final AppDatabase _db;

  /// 全部账户（不带余额），记账面板选择账户用。
  Future<List<Account>> all() {
    return (_db.select(_db.accounts)
          ..orderBy([
            (t) => OrderingTerm(expression: t.sortOrder),
            (t) => OrderingTerm(expression: t.name),
          ]))
        .get();
  }

  Stream<List<AccountBalance>> watchWithBalances() async* {
    yield await withBalances();
    yield* _db.tableUpdates().asyncMap((_) => withBalances());
  }

  Future<List<AccountBalance>> withBalances() async {
    final accounts = await (_db.select(_db.accounts)
          ..orderBy([
            (t) => OrderingTerm(expression: t.sortOrder),
            (t) => OrderingTerm(expression: t.name),
          ]))
        .get();

    final rows = await _db
        .customSelect(
          '''
          SELECT account_id, type, SUM(amount_cents) AS total, COUNT(*) AS n
          FROM transactions
          WHERE account_id IS NOT NULL
          GROUP BY account_id, type
          ''',
        )
        .get();

    final expense = <String, int>{};
    final income = <String, int>{};
    final counts = <String, int>{};
    for (final row in rows) {
      final id = row.read<String>('account_id');
      final total = row.read<int>('total');
      counts.update(id, (v) => v + row.read<int>('n'), ifAbsent: () => row.read<int>('n'));
      if (row.read<String>('type') == EntryType.income.name) {
        income.update(id, (v) => v + total, ifAbsent: () => total);
      } else {
        expense.update(id, (v) => v + total, ifAbsent: () => total);
      }
    }

    return [
      for (final account in accounts)
        AccountBalance(
          account: account,
          expenseCents: expense[account.id] ?? 0,
          incomeCents: income[account.id] ?? 0,
          count: counts[account.id] ?? 0,
        ),
    ];
  }

  /// 按名称复用或新建账户（导入时用）。新账户初始余额一律 0。
  Future<Account> ensure({required String name, AccountType type = AccountType.wallet}) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) {
      throw ArgumentError.value(name, 'name', '账户名不能为空');
    }
    final existing = await (_db.select(_db.accounts)
          ..where((t) => t.name.equals(trimmed)))
        .getSingleOrNull();
    if (existing != null) return existing;

    final maxOrder = await _db
        .customSelect('SELECT COALESCE(MAX(sort_order), -1) AS m FROM accounts')
        .getSingle();
    // id 由名称推导：连续创建多个账户时不会撞出「插入了但查不到」的竞态
    final id = 'acc-$trimmed';
    await _db.into(_db.accounts).insert(
          AccountsCompanion.insert(
            id: id,
            name: trimmed,
            type: Value(type),
            initialBalanceCents: const Value(0),
            sortOrder: Value(maxOrder.read<int>('m') + 1),
          ),
        );
    return (await (_db.select(_db.accounts)..where((t) => t.id.equals(id)))
        .getSingle());
  }

  Future<Account?> byId(String id) =>
      (_db.select(_db.accounts)..where((t) => t.id.equals(id))).getSingleOrNull();
}
