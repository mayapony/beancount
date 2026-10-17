import 'package:bean_count/data/db/app_database.dart';
import 'package:bean_count/data/db/connection.dart';
import 'package:bean_count/data/db/enums.dart';
import 'package:bean_count/data/repositories/category_repository.dart';
import 'package:bean_count/data/repositories/insights_repository.dart';
import 'package:bean_count/data/repositories/transaction_repository.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late AppDatabase db;
  late TransactionRepository transactions;
  late CategoryRepository categories;
  late InsightsRepository insights;

  setUp(() async {
    db = AppDatabase(openInMemoryConnection());
    transactions = TransactionRepository(db);
    categories = CategoryRepository(db);
    insights = InsightsRepository(db);
    await db.select(db.transactions).get(); // 建库 + 种子
  });

  tearDown(() async => db.close());

  Future<String> cat(String name, CategoryType type, {String? parentId}) async =>
      (await categories.ensure(name: name, type: type, parentId: parentId)).id;

  test('总额等于库里支出之和，收入不计入分类占比', () async {
    final food = await cat('餐饮', CategoryType.expense);
    final salary = await cat('工资', CategoryType.income);

    await transactions.create(
      NewTransaction(
        type: EntryType.expense,
        amountCents: 3850,
        categoryId: food,
        happenedAt: DateTime(2026, 10, 17, 12),
        note: '午餐',
      ),
    );
    await transactions.create(
      NewTransaction(
        type: EntryType.expense,
        amountCents: 1200,
        categoryId: food,
        happenedAt: DateTime(2026, 10, 16, 9),
        note: '早餐',
      ),
    );
    await transactions.create(
      NewTransaction(
        type: EntryType.income,
        amountCents: 500000,
        categoryId: salary,
        happenedAt: DateTime(2026, 10, 15, 10),
        note: '工资',
      ),
    );

    final data = await insights.load(
      period: InsightsPeriod.month,
      now: DateTime(2026, 10, 17),
    );

    expect(data.expenseCents, 3850 + 1200);
    expect(data.incomeCents, 500000);
    expect(data.categories.single.category.name, '餐饮');
    expect(data.categories.single.cents, 5050);
    expect(data.activeDays, 2);
  });

  test('二级分类上卷到一级分类', () async {
    final food = await cat('餐饮', CategoryType.expense);
    await categories.ensure(
      name: '午餐',
      type: CategoryType.expense,
      parentId: food,
    );
    final lunch = await cat('午餐', CategoryType.expense, parentId: food);

    await transactions.create(
      NewTransaction(
        type: EntryType.expense,
        amountCents: 2000,
        categoryId: lunch,
        happenedAt: DateTime(2026, 10, 17, 12),
        note: '午餐',
      ),
    );

    final data = await insights.load(
      period: InsightsPeriod.month,
      now: DateTime(2026, 10, 17),
    );

    expect(data.categories, hasLength(1));
    expect(data.categories.single.category.name, '餐饮');
    expect(data.categories.single.cents, 2000);
  });

  test('月份范围只算本月，趋势按天分桶', () async {
    final food = await cat('餐饮', CategoryType.expense);
    for (final at in [
      DateTime(2026, 9, 30, 23),
      DateTime(2026, 10, 1, 8),
      DateTime(2026, 10, 31, 23),
      DateTime(2026, 11, 1, 0),
    ]) {
      await transactions.create(
        NewTransaction(
          type: EntryType.expense,
          amountCents: 1000,
          categoryId: food,
          happenedAt: at,
          note: at.toIso8601String(),
        ),
      );
    }

    final data = await insights.load(
      period: InsightsPeriod.month,
      now: DateTime(2026, 10, 17),
    );

    expect(data.expenseCents, 2000);
    expect(data.trend, hasLength(31), reason: '10 月有 31 天');
    expect(data.trend.first.label, '1');
    expect(data.trend[0].cents, 1000);
    expect(data.trend.last.label, '31');
    expect(data.trend.last.cents, 1000);
    expect(data.rangeLabel, '2026年10月');
  });

  test('年度范围按月分桶，全部时间从最早一笔开始', () async {
    final food = await cat('餐饮', CategoryType.expense);
    await transactions.create(
      NewTransaction(
        type: EntryType.expense,
        amountCents: 3000,
        categoryId: food,
        happenedAt: DateTime(2025, 3, 5, 12),
        note: '旧账',
      ),
    );
    await transactions.create(
      NewTransaction(
        type: EntryType.expense,
        amountCents: 2000,
        categoryId: food,
        happenedAt: DateTime(2026, 10, 5, 12),
        note: '新账',
      ),
    );

    final year = await insights.load(
      period: InsightsPeriod.year,
      now: DateTime(2026, 10, 17),
    );
    expect(year.expenseCents, 2000);
    expect(year.trend, hasLength(12));

    final all = await insights.load(
      period: InsightsPeriod.all,
      now: DateTime(2026, 10, 17),
    );
    expect(all.expenseCents, 5000);
    expect(all.trend.first.label, '3月');
    expect(all.trend.first.cents, 3000);
  });
}
