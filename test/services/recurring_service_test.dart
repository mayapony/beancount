import 'package:bean_count/data/db/app_database.dart';
import 'package:bean_count/data/db/connection.dart';
import 'package:bean_count/data/db/enums.dart';
import 'package:bean_count/data/repositories/account_repository.dart';
import 'package:bean_count/data/repositories/category_repository.dart';
import 'package:bean_count/data/repositories/recurring_repository.dart';
import 'package:bean_count/data/repositories/transaction_repository.dart';
import 'package:bean_count/services/recurring/recurring_schedule.dart';
import 'package:bean_count/services/recurring/recurring_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late AppDatabase db;
  late RecurringRepository rules;
  late TransactionRepository transactions;
  late CategoryRepository categories;
  late AccountRepository accounts;
  late RecurringService service;

  setUp(() async {
    db = AppDatabase(openInMemoryConnection());
    rules = RecurringRepository(db);
    transactions = TransactionRepository(db);
    categories = CategoryRepository(db);
    accounts = AccountRepository(db);
    service = RecurringService(rules: rules, transactions: transactions);
    await db.select(db.categories).get();
  });

  tearDown(() async => db.close());

  Future<String> foodId() async =>
      (await categories.findByName('餐饮', CategoryType.expense))!.id;

  test('每月 31 日在 2 月落到月末', () {
    expect(occurrenceDateIn(2026, 2, 31), DateTime(2026, 2, 28));
    expect(occurrenceDateIn(2024, 2, 31), DateTime(2024, 2, 29));
    expect(occurrenceDateIn(2026, 4, 31), DateTime(2026, 4, 30));
    expect(occurrenceDateIn(2026, 5, 5), DateTime(2026, 5, 5));
  });

  test('补记范围：起始 7 月、10 月 8 日 → 4 期；当月未到日子不补', () async {
    final rule = await rules.create(
      type: EntryType.expense,
      amountCents: 250000,
      categoryId: await foodId(),
      note: '房租',
      dayOfMonth: 5,
      startYear: 2026,
      startMonth: 7,
    );

    final october8 = DateTime(2026, 10, 8, 12);
    expect(occurrencesUntil(rule, october8), [
      DateTime(2026, 7, 5),
      DateTime(2026, 8, 5),
      DateTime(2026, 9, 5),
      DateTime(2026, 10, 5),
    ]);

    // 10 月 3 日时，10 月还没到日子
    final october3 = DateTime(2026, 10, 3, 12);
    expect(occurrencesUntil(rule, october3), hasLength(3));
  });

  test('下次执行日严格晚于今天', () async {
    final rule = await rules.create(
      type: EntryType.expense,
      amountCents: 1000,
      categoryId: await foodId(),
      dayOfMonth: 5,
      startYear: 2026,
      startMonth: 1,
    );

    expect(nextDueDate(rule, DateTime(2026, 10, 8)), DateTime(2026, 11, 5));
    expect(nextDueDate(rule, DateTime(2026, 10, 5)), DateTime(2026, 11, 5));
    expect(nextDueDate(rule, DateTime(2026, 10, 1)), DateTime(2026, 10, 5));
  });

  test('规则增删改与启用状态', () async {
    final rule = await rules.create(
      type: EntryType.expense,
      amountCents: 9900,
      categoryId: await foodId(),
      note: '宽带',
      dayOfMonth: 20,
      startYear: 2026,
      startMonth: 9,
    );
    expect(rule.enabled, isTrue);
    expect(frequencyLabel(rule), '每月 20 日');

    await rules.update(rule.id, amountCents: 10800, note: '宽带升级');
    final updated = (await rules.byId(rule.id))!;
    expect(updated.amountCents, 10800);
    expect(updated.note, '宽带升级');

    await rules.setEnabled(rule.id, false);
    expect(await rules.allEnabled(), isEmpty);

    await rules.delete(rule.id);
    expect(await rules.byId(rule.id), isNull);
  });

  test('规则校验：支出缺分类被拒、转账两端相同被拒', () async {
    await expectLater(
      rules.create(
        type: EntryType.expense,
        amountCents: 100,
        dayOfMonth: 1,
        startYear: 2026,
        startMonth: 1,
      ),
      throwsA(isA<ArgumentError>()),
    );

    final wallets = await accounts.all();
    await expectLater(
      rules.create(
        type: EntryType.transfer,
        amountCents: 100,
        accountId: wallets.first.id,
        toAccountId: wallets.first.id,
        dayOfMonth: 1,
        startYear: 2026,
        startMonth: 1,
      ),
      throwsA(isA<ArgumentError>()),
    );
  });

  test('首次补记从起始月补齐，再运行不重复', () async {
    await rules.create(
      type: EntryType.expense,
      amountCents: 250000,
      categoryId: await foodId(),
      note: '房租',
      dayOfMonth: 5,
      startYear: 2026,
      startMonth: 7,
    );

    final first = await service.applyDue(now: DateTime(2026, 10, 8, 12));
    expect(first.created, 4);
    expect(first.skipped, 0);
    expect(await transactions.count(), 4);

    final second = await service.applyDue(now: DateTime(2026, 10, 8, 12));
    expect(second.created, 0);
    expect(second.skipped, 4);
    expect(await transactions.count(), 4, reason: '同一天再开会话不能重复补');

    // 补记出来的交易带规则与期数标记
    final rows = await transactions.exportRows();
    expect(rows.every((r) => r.transaction.recurringRuleId != null), isTrue);
    expect(
      rows.map((r) => r.transaction.recurringPeriod).toSet(),
      {'2026-07', '2026-08', '2026-09', '2026-10'},
    );
  });

  test('用户改过自动补记的交易，也不会被再次补记', () async {
    await rules.create(
      type: EntryType.expense,
      amountCents: 250000,
      categoryId: await foodId(),
      note: '房租',
      dayOfMonth: 5,
      startYear: 2026,
      startMonth: 9,
    );
    await service.applyDue(now: DateTime(2026, 10, 8, 12));
    expect(await transactions.count(), 2);

    final first = (await transactions.exportRows()).first.transaction;
    await transactions.update(
      first.id,
      TransactionEdit(
        type: EntryType.expense,
        amountCents: 300000,
        categoryId: first.categoryId,
        happenedAt: first.happenedAt,
        accountId: first.accountId,
        note: '房租（涨价）',
      ),
    );

    final again = await service.applyDue(now: DateTime(2026, 10, 8, 12));
    expect(again.created, 0);
    expect(await transactions.count(), 2, reason: '改过的期数仍算已补');
    final updated = await transactions.byId(first.id);
    expect(updated!.amountCents, 300000);
  });

  test('暂停的规则不补记', () async {
    final rule = await rules.create(
      type: EntryType.expense,
      amountCents: 1000,
      categoryId: await foodId(),
      dayOfMonth: 5,
      startYear: 2026,
      startMonth: 10,
    );
    await rules.setEnabled(rule.id, false);

    final result = await service.applyDue(now: DateTime(2026, 10, 8));
    expect(result.created, 0);
    expect(await transactions.count(), 0);
  });

  test('转账规则补记出来的是转账，不计收支', () async {
    final wallets = await accounts.all();
    final to = await accounts.ensure(name: '支付宝');
    await rules.create(
      type: EntryType.transfer,
      amountCents: 100000,
      accountId: wallets.first.id,
      toAccountId: to.id,
      note: '每月转存',
      dayOfMonth: 1,
      startYear: 2026,
      startMonth: 10,
    );

    final result = await service.applyDue(now: DateTime(2026, 10, 8));
    expect(result.created, 1);

    final row = (await transactions.exportRows()).single;
    expect(row.transaction.type, EntryType.transfer);
    expect(row.toAccountName, '支付宝');
    expect(row.categoryPath, isEmpty);

    final groups = await transactions.dayGroups(year: 2026, month: 10);
    expect(groups.single.expenseCents, 0, reason: '转账不算支出');
  });

  test('编辑规则只影响未来，不改历史', () async {
    final rule = await rules.create(
      type: EntryType.expense,
      amountCents: 250000,
      categoryId: await foodId(),
      note: '房租',
      dayOfMonth: 5,
      startYear: 2026,
      startMonth: 9,
    );
    await service.applyDue(now: DateTime(2026, 10, 8));
    final before = await transactions.exportRows();
    expect(before.map((r) => r.transaction.amountCents).toSet(), {250000});

    await rules.update(rule.id, amountCents: 280000);
    expect(await transactions.count(), 2, reason: '改规则不补历史');

    final later = await service.applyDue(now: DateTime(2026, 11, 8));
    expect(later.created, 1);
    final newest = (await transactions.exportRows()).last;
    expect(newest.transaction.amountCents, 280000);
  });
}
