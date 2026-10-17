import 'package:drift/drift.dart';

import '../db/app_database.dart';
import '../db/enums.dart';

/// 循环规则仓储：只做增删改查与「哪几期已经补过」的判据，不含补记逻辑。
class RecurringRepository {
  RecurringRepository(this._db);

  final AppDatabase _db;

  Future<List<RecurringRule>> all() {
    return (_db.select(_db.recurringRules)
          ..orderBy([
            (t) => OrderingTerm(expression: t.enabled, mode: OrderingMode.desc),
            (t) => OrderingTerm(expression: t.createdAt),
          ]))
        .get();
  }

  Future<List<RecurringRule>> allEnabled() {
    return (_db.select(_db.recurringRules)
          ..where((t) => t.enabled.equals(true))
          ..orderBy([(t) => OrderingTerm(expression: t.createdAt)]))
        .get();
  }

  Future<RecurringRule?> byId(String id) {
    return (_db.select(_db.recurringRules)..where((t) => t.id.equals(id)))
        .getSingleOrNull();
  }

  Future<RecurringRule> create({
    required EntryType type,
    required int amountCents,
    String? categoryId,
    String? accountId,
    String? toAccountId,
    String note = '',
    required int dayOfMonth,
    required int startYear,
    required int startMonth,
    bool enabled = true,
  }) async {
    if (amountCents <= 0) {
      throw ArgumentError.value(amountCents, 'amountCents', '金额必须大于 0');
    }
    if (dayOfMonth < 1 || dayOfMonth > 31) {
      throw ArgumentError.value(dayOfMonth, 'dayOfMonth', '执行日必须在 1–31 之间');
    }
    if (type == EntryType.transfer) {
      if (accountId == null || toAccountId == null || accountId == toAccountId) {
        throw ArgumentError('转账规则需要两端不同账户');
      }
    } else if (categoryId == null) {
      throw ArgumentError('支出/收入规则必须有分类');
    }

    final id = 'rec-${DateTime.now().microsecondsSinceEpoch}-${_seq++}';
    await _db.into(_db.recurringRules).insert(
          RecurringRulesCompanion.insert(
            id: id,
            type: type,
            amountCents: amountCents,
            categoryId: Value(categoryId),
            accountId: Value(accountId),
            toAccountId: Value(toAccountId),
            note: Value(note.trim()),
            dayOfMonth: dayOfMonth,
            startYear: startYear,
            startMonth: startMonth,
            enabled: Value(enabled),
          ),
        );
    return (await byId(id))!;
  }

  Future<void> update(
    String id, {
    EntryType? type,
    int? amountCents,
    String? categoryId,
    bool clearCategory = false,
    String? accountId,
    bool clearAccount = false,
    String? toAccountId,
    bool clearToAccount = false,
    String? note,
    int? dayOfMonth,
    int? startYear,
    int? startMonth,
    bool? enabled,
  }) async {
    if (amountCents != null && amountCents <= 0) {
      throw ArgumentError.value(amountCents, 'amountCents', '金额必须大于 0');
    }
    await (_db.update(_db.recurringRules)..where((t) => t.id.equals(id))).write(
      RecurringRulesCompanion(
        type: type == null ? const Value.absent() : Value(type),
        amountCents:
            amountCents == null ? const Value.absent() : Value(amountCents),
        categoryId: clearCategory
            ? const Value(null)
            : (categoryId == null ? const Value.absent() : Value(categoryId)),
        accountId: clearAccount
            ? const Value(null)
            : (accountId == null ? const Value.absent() : Value(accountId)),
        toAccountId: clearToAccount
            ? const Value(null)
            : (toAccountId == null ? const Value.absent() : Value(toAccountId)),
        note: note == null ? const Value.absent() : Value(note.trim()),
        dayOfMonth:
            dayOfMonth == null ? const Value.absent() : Value(dayOfMonth),
        startYear: startYear == null ? const Value.absent() : Value(startYear),
        startMonth:
            startMonth == null ? const Value.absent() : Value(startMonth),
        enabled: enabled == null ? const Value.absent() : Value(enabled),
      ),
    );
  }

  Future<void> setEnabled(String id, bool enabled) =>
      update(id, enabled: enabled);

  Future<void> delete(String id) async {
    await (_db.delete(_db.recurringRules)..where((t) => t.id.equals(id))).go();
  }

  /// 某条规则的某一期是否已经有交易（补记幂等的判据）。
  Future<bool> hasPeriod(String ruleId, String period) async {
    final row = await (_db.select(_db.transactions)
          ..where(
            (t) =>
                t.recurringRuleId.equals(ruleId) &
                t.recurringPeriod.equals(period),
          )
          ..limit(1))
        .getSingleOrNull();
    return row != null;
  }

  static int _seq = 0;
}
