import 'package:bean_count/data/db/app_database.dart';
import 'package:bean_count/data/db/connection.dart';
import 'package:bean_count/data/db/enums.dart';
import 'package:bean_count/data/repositories/account_repository.dart';
import 'package:bean_count/data/repositories/category_repository.dart';
import 'package:bean_count/data/repositories/net_worth_repository.dart';
import 'package:bean_count/data/repositories/transaction_repository.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late AppDatabase db;
  late NetWorthRepository repo;
  late TransactionRepository transactions;
  late CategoryRepository categories;
  late AccountRepository accounts;

  final now = DateTime(2026, 10, 15, 12);

  setUp(() async {
    db = AppDatabase(openInMemoryConnection());
    repo = NetWorthRepository(db);
    transactions = TransactionRepository(db);
    categories = CategoryRepository(db);
    accounts = AccountRepository(db);
    await db.select(db.categories).get();
  });

  tearDown(() async => db.close());

  Future<String> cat(String name, {CategoryType type = CategoryType.expense}) async =>
      (await categories.findByName(name, type))!.id;

  test('收入让净值上升、支出让它下降', () async {
    await transactions.create(
      NewTransaction(
        type: EntryType.income,
        amountCents: 500000,
        categoryId: await cat('工资', type: CategoryType.income),
        happenedAt: DateTime(2026, 10, 5),
        note: '工资',
      ),
    );
    await transactions.create(
      NewTransaction(
        type: EntryType.expense,
        amountCents: 120000,
        categoryId: await cat('餐饮'),
        happenedAt: DateTime(2026, 10, 8),
        note: '吃饭',
      ),
    );

    final series = await repo.load(range: NetWorthRange.sixMonths, now: now);
    expect(series.current, 500000 - 120000);
  });

  test('转账不影响净值曲线', () async {
    final from = (await accounts.all()).first;
    final to = await accounts.ensure(name: '支付宝');

    final before = await repo.load(range: NetWorthRange.thisYear, now: now);
    await transactions.create(
      NewTransaction(
        type: EntryType.transfer,
        amountCents: 50000,
        accountId: from.id,
        toAccountId: to.id,
        happenedAt: DateTime(2026, 10, 9),
        note: '转存',
      ),
    );
    final after = await repo.load(range: NetWorthRange.thisYear, now: now);

    expect(after.current, before.current, reason: '两端抵消');
    expect(
      after.points.map((p) => p.cents).toList(),
      before.points.map((p) => p.cents).toList(),
    );
  });

  test('初始余额当作基线，不计入任何一个月', () async {
    final account = (await accounts.all()).first;
    await accounts.update(account.id, initialBalanceCents: 100000);

    final series = await repo.load(range: NetWorthRange.sixMonths, now: now);
    expect(series.hasData, isFalse, reason: '没有交易时不算"有数据"');
    expect(series.points, hasLength(6), reason: '但月份序列仍然生成');
    expect(series.current, 100000, reason: '净值就是初始余额');
    expect(
      series.points.every((p) => p.cents == 100000),
      isTrue,
      reason: '初始余额不该被算成某个月的增量',
    );
  });

  test('三档范围的点数：近6月=6、今年=10、全部从最早一笔起', () async {
    await transactions.create(
      NewTransaction(
        type: EntryType.expense,
        amountCents: 1000,
        categoryId: await cat('餐饮'),
        happenedAt: DateTime(2024, 3, 10),
        note: '很久以前',
      ),
    );
    await transactions.create(
      NewTransaction(
        type: EntryType.expense,
        amountCents: 2000,
        categoryId: await cat('餐饮'),
        happenedAt: DateTime(2026, 10, 1),
        note: '最近',
      ),
    );

    final six = await repo.load(range: NetWorthRange.sixMonths, now: now);
    expect(six.points, hasLength(6));
    expect(six.points.first.at, DateTime(2026, 5));
    expect(six.points.last.at, DateTime(2026, 10));

    final year = await repo.load(range: NetWorthRange.thisYear, now: now);
    expect(year.points, hasLength(10));
    expect(year.points.first.at, DateTime(2026, 1));

    final all = await repo.load(range: NetWorthRange.all, now: now);
    expect(all.points.first.at, DateTime(2024, 3));
    expect(all.points.last.at, DateTime(2026, 10));
    expect(all.current, -3000);
  });

  test('changeCents 是首尾差', () async {
    await transactions.create(
      NewTransaction(
        type: EntryType.income,
        amountCents: 5000,
        categoryId: await cat('工资', type: CategoryType.income),
        happenedAt: DateTime(2026, 9, 1),
      ),
    );
    await transactions.create(
      NewTransaction(
        type: EntryType.income,
        amountCents: 7500,
        categoryId: await cat('工资', type: CategoryType.income),
        happenedAt: DateTime(2026, 10, 1),
      ),
    );

    final series = await repo.load(range: NetWorthRange.sixMonths, now: now);
    // 区间第一点是 5 月，那时两笔都还没发生
    expect(series.startValue, 0);
    expect(series.current, 12500);
    expect(series.changeCents, 12500);
  });

  test('空账本：isEmpty 为真', () async {
    final series = await repo.load(range: NetWorthRange.sixMonths, now: now);
    expect(series.isEmpty, isTrue);
  });

  test('订阅随账目变化重发', () async {
    final emissions =
        repo.watch(range: NetWorthRange.sixMonths, now: now).take(2).toList();
    await Future<void>.delayed(Duration.zero);
    await transactions.create(
      NewTransaction(
        type: EntryType.income,
        amountCents: 3000,
        categoryId: await cat('工资', type: CategoryType.income),
        happenedAt: DateTime(2026, 10, 2),
      ),
    );

    final snapshots = await emissions;
    expect(snapshots.first.current, 0);
    expect(snapshots.last.current, 3000);
  });
}
