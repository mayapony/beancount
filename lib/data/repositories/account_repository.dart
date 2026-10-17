import 'package:drift/drift.dart';

import '../db/app_database.dart';
import '../db/enums.dart';

/// 账户 + 由交易推导出来的余额。
class AccountBalance {
  const AccountBalance({
    required this.account,
    required this.expenseCents,
    required this.incomeCents,
    this.transferOutCents = 0,
    this.transferInCents = 0,
    this.count = 0,
  });

  final Account account;
  final int expenseCents;
  final int incomeCents;

  /// 转出/转入合计（转账不计入收支，但会改变余额）。
  final int transferOutCents;
  final int transferInCents;

  /// 关联的交易笔数（展示用；转账两端都算一笔）。
  final int count;

  /// 余额 = 初始余额 + 收入 − 支出 − 转出 + 转入。**不单独存**，永远不会漂移。
  int get balanceCents =>
      account.initialBalanceCents +
      incomeCents -
      expenseCents -
      transferOutCents +
      transferInCents;
}

/// 一张信用卡的还款提醒。
class CardDue {
  const CardDue({
    required this.account,
    required this.dueDate,
    required this.owedCents,
    required this.daysLeft,
  });

  final Account account;
  final DateTime dueDate;

  /// 应还金额（正数）。
  final int owedCents;

  /// 距还款日的天数：0 表示今天，负数表示已逾期。
  final int daysLeft;

  bool get isToday => daysLeft == 0;
  bool get isOverdue => daysLeft < 0;
  bool get isUrgent => daysLeft <= 3;
}

/// 账户被交易引用时抛出：删除会被拒绝，并告诉调用方有多少笔。
class AccountInUseException implements Exception {
  AccountInUseException(this.accountId, this.count);

  final String accountId;
  final int count;

  @override
  String toString() => '有 $count 笔交易在使用该账户，先迁移再删除';
}

/// 账户重名：新建或改名时撞上已有账户。
class DuplicateAccountNameException implements Exception {
  DuplicateAccountNameException(this.name);

  final String name;

  @override
  String toString() => '已有同名账户「$name」';
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
    final transferOut = <String, int>{};
    final counts = <String, int>{};
    for (final row in rows) {
      final id = row.read<String>('account_id');
      final total = row.read<int>('total');
      final count = row.read<int>('n');
      counts.update(id, (v) => v + count, ifAbsent: () => count);
      switch (row.read<String>('type')) {
        case 'income':
          income.update(id, (v) => v + total, ifAbsent: () => total);
        case 'expense':
          expense.update(id, (v) => v + total, ifAbsent: () => total);
        case 'transfer':
          transferOut.update(id, (v) => v + total, ifAbsent: () => total);
      }
    }

    // 转账的「转入侧」：同一个账户可能是别人转进来的那一端
    final incoming = await _db
        .customSelect(
          '''
          SELECT to_account_id, SUM(amount_cents) AS total, COUNT(*) AS n
          FROM transactions
          WHERE to_account_id IS NOT NULL
          GROUP BY to_account_id
          ''',
        )
        .get();
    final transferIn = <String, int>{};
    for (final row in incoming) {
      final id = row.read<String>('to_account_id');
      transferIn.update(id, (v) => v + row.read<int>('total'),
          ifAbsent: () => row.read<int>('total'));
      counts.update(id, (v) => v + row.read<int>('n'),
          ifAbsent: () => row.read<int>('n'));
    }

    return [
      for (final account in accounts)
        AccountBalance(
          account: account,
          expenseCents: expense[account.id] ?? 0,
          incomeCents: income[account.id] ?? 0,
          transferOutCents: transferOut[account.id] ?? 0,
          transferInCents: transferIn[account.id] ?? 0,
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

  /// 用户在账户管理里新建：名称必须唯一，id 与名称解耦（改名不会动主键）。
  Future<Account> create({
    required String name,
    AccountType type = AccountType.wallet,
    int initialBalanceCents = 0,
    int? billingDay,
    int? dueDay,
  }) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) throw ArgumentError.value(name, 'name', '账户名不能为空');
    _checkDay(billingDay, 'billingDay');
    _checkDay(dueDay, 'dueDay');
    await _ensureNameFree(trimmed);

    final maxOrder = await _db
        .customSelect('SELECT COALESCE(MAX(sort_order), -1) AS m FROM accounts')
        .getSingle();
    final id = 'acc-${DateTime.now().microsecondsSinceEpoch}-${_seq++}';
    await _db.into(_db.accounts).insert(
          AccountsCompanion.insert(
            id: id,
            name: trimmed,
            type: Value(type),
            initialBalanceCents: Value(initialBalanceCents),
            billingDay: Value(billingDay),
            dueDay: Value(dueDay),
            sortOrder: Value(maxOrder.read<int>('m') + 1),
          ),
        );
    return (await byId(id))!;
  }

  /// 改名 / 改类型 / 改期初余额。余额仍然由期初 + 交易推导，这里不写任何余额字段。
  Future<void> update(
    String id, {
    String? name,
    AccountType? type,
    int? initialBalanceCents,
    int? billingDay,
    bool clearBillingDay = false,
    int? dueDay,
    bool clearDueDay = false,
  }) async {
    _checkDay(billingDay, 'billingDay');
    _checkDay(dueDay, 'dueDay');
    final trimmed = name?.trim();
    if (trimmed != null) {
      if (trimmed.isEmpty) throw ArgumentError.value(name, 'name', '账户名不能为空');
      final current = await byId(id);
      if (current != null && current.name != trimmed) {
        await _ensureNameFree(trimmed, exceptId: id);
      }
    }

    await (_db.update(_db.accounts)..where((t) => t.id.equals(id))).write(
      AccountsCompanion(
        name: trimmed == null ? const Value.absent() : Value(trimmed),
        type: type == null ? const Value.absent() : Value(type),
        initialBalanceCents: initialBalanceCents == null
            ? const Value.absent()
            : Value(initialBalanceCents),
        billingDay: clearBillingDay
            ? const Value(null)
            : (billingDay == null ? const Value.absent() : Value(billingDay)),
        dueDay: clearDueDay
            ? const Value(null)
            : (dueDay == null ? const Value.absent() : Value(dueDay)),
      ),
    );
  }

  /// 日号只允许 1–28：避开大小月与 2 月的漂移。
  static void _checkDay(int? day, String field) {
    if (day == null) return;
    if (day < 1 || day > 28) {
      throw ArgumentError.value(day, field, '日期只能是 1–28');
    }
  }

  /// 还款提醒：只算「信用卡 + 设了还款日 + 有欠款」的账户。
  ///
  /// 顺序按剩余天数升序（同一天再按应还金额降序），最急的排最前。
  Future<List<CardDue>> dueReminders({DateTime? now}) async {
    return cardDuesOf(await withBalances(), now: now);
  }

  /// 纯函数版：页面已经拿到余额时不必再查库。
  static List<CardDue> cardDuesOf(
    List<AccountBalance> balances, {
    DateTime? now,
  }) {
    final reference = now ?? DateTime.now();
    final today = DateTime(reference.year, reference.month, reference.day);

    final result = <CardDue>[];
    for (final item in balances) {
      final dueDay = item.account.dueDay;
      if (item.account.type != AccountType.credit || dueDay == null) continue;
      if (item.balanceCents >= 0) continue; // 已还清或多还，不提醒

      var due = DateTime(today.year, today.month, dueDay);
      if (due.isBefore(today)) {
        // DateTime 会把 month = 13 规整成次年 1 月，跨年不用特判
        due = DateTime(today.year, today.month + 1, dueDay);
      }
      result.add(
        CardDue(
          account: item.account,
          dueDate: due,
          owedCents: -item.balanceCents,
          daysLeft: due.difference(today).inDays,
        ),
      );
    }

    result.sort((a, b) {
      final byDays = a.daysLeft.compareTo(b.daysLeft);
      if (byDays != 0) return byDays;
      return b.owedCents.compareTo(a.owedCents);
    });
    return result;
  }

  /// 删除账户：被交易引用时拒绝，避免出现"交易指向不存在账户"的记录。
  Future<void> delete(String id) async {
    final used = await usageCount(id);
    if (used > 0) {
      throw AccountInUseException(id, used);
    }
    await (_db.delete(_db.accounts)..where((t) => t.id.equals(id))).go();
  }

  Future<int> usageCount(String accountId) async {
    final row = await _db.customSelect(
      'SELECT COUNT(*) AS c FROM transactions '
      'WHERE account_id = ? OR to_account_id = ?',
      variables: [
        Variable.withString(accountId),
        Variable.withString(accountId),
      ],
    ).getSingle();
    return row.read<int>('c');
  }

  Future<void> _ensureNameFree(String name, {String? exceptId}) async {
    final existing = await (_db.select(_db.accounts)
          ..where((t) => t.name.equals(name)))
        .getSingleOrNull();
    if (existing != null && existing.id != exceptId) {
      throw DuplicateAccountNameException(name);
    }
  }

  static int _seq = 0;
}
