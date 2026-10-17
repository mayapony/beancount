import 'package:bean_count/data/db/app_database.dart';
import 'package:bean_count/data/db/connection.dart';
import 'package:bean_count/data/db/enums.dart';
import 'package:bean_count/data/repositories/account_repository.dart';
import 'package:bean_count/data/repositories/category_repository.dart';
import 'package:bean_count/data/repositories/insights_repository.dart';
import 'package:bean_count/data/repositories/transaction_repository.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late AppDatabase db;
  late TransactionRepository transactions;
  late CategoryRepository categories;
  late AccountRepository accounts;
  late InsightsRepository insights;

  setUp(() async {
    db = AppDatabase(openInMemoryConnection());
    transactions = TransactionRepository(db);
    categories = CategoryRepository(db);
    accounts = AccountRepository(db);
    insights = InsightsRepository(db);
    await db.select(db.categories).get();
  });

  tearDown(() async => db.close());

  Future<String> food() async =>
      (await categories.findByName('餐饮', CategoryType.expense))!.id;

  test('USD 100 @ 7.25：存原币与汇率，本位币 725 元', () async {
    final card = await accounts.create(name: 'USD 卡', currency: 'USD');
    final result = await transactions.create(
      NewTransaction(
        type: EntryType.expense,
        amountCents: 10000,
        originalAmountCents: 10000,
        currency: 'USD',
        ratePpm: 7250000,
        categoryId: await food(),
        accountId: card.id,
        happenedAt: DateTime(2026, 10, 8, 12),
        note: '晚饭',
      ),
    );

    final row = (await transactions.byId(result.transactionId))!.transaction;
    expect(row.amountCents, 72500);
    expect(row.originalAmountCents, 10000);
    expect(row.currency, 'USD');
    expect(row.ratePpm, 7250000);
  });

  test('同月合计按本位币：725 + 100 = 825', () async {
    await transactions.create(
      NewTransaction(
        type: EntryType.expense,
        amountCents: 10000,
        currency: 'USD',
        ratePpm: 7250000,
        categoryId: await food(),
        happenedAt: DateTime(2026, 10, 8, 12),
        note: 'USD 晚饭',
      ),
    );
    await transactions.create(
      NewTransaction(
        type: EntryType.expense,
        amountCents: 10000,
        categoryId: await food(),
        happenedAt: DateTime(2026, 10, 9, 12),
        note: 'CNY 午饭',
      ),
    );

    final groups = await transactions.dayGroups(year: 2026, month: 10);
    final total = groups.fold<int>(0, (sum, g) => sum + g.expenseCents);
    expect(total, 82500);

    final stats = await insights.load(
      period: InsightsPeriod.month,
      now: DateTime(2026, 10, 15),
    );
    expect(stats.expenseCents, 82500);
  });

  test('外币缺汇率被拒', () async {
    await expectLater(
      transactions.create(
        NewTransaction(
          type: EntryType.expense,
          amountCents: 10000,
          currency: 'USD',
          categoryId: await food(),
          happenedAt: DateTime(2026, 10, 8, 12),
        ),
      ),
      throwsA(isA<ArgumentError>()),
    );
    expect(await transactions.count(), 0);
  });

  test('CNY 交易保持原样（无原币字段）', () async {
    final result = await transactions.create(
      NewTransaction(
        type: EntryType.expense,
        amountCents: 3850,
        categoryId: await food(),
        happenedAt: DateTime(2026, 10, 8, 12),
        note: '牛肉面',
      ),
    );

    final row = (await transactions.byId(result.transactionId))!.transaction;
    expect(row.amountCents, 3850);
    expect(row.currency, 'CNY');
    expect(row.originalAmountCents, isNull);
    expect(row.ratePpm, isNull);
  });
}
