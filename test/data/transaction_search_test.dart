import 'package:bean_count/data/db/app_database.dart';
import 'package:bean_count/data/db/connection.dart';
import 'package:bean_count/data/db/enums.dart';
import 'package:bean_count/data/repositories/account_repository.dart';
import 'package:bean_count/data/repositories/category_repository.dart';
import 'package:bean_count/data/repositories/ledger_filter.dart';
import 'package:bean_count/data/repositories/transaction_repository.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late AppDatabase db;
  late TransactionRepository repo;
  late CategoryRepository categories;
  late AccountRepository accounts;

  final now = DateTime(2026, 10, 18, 12);

  setUp(() async {
    db = AppDatabase(openInMemoryConnection());
    categories = CategoryRepository(db);
    accounts = AccountRepository(db);
    repo = TransactionRepository(db);
    await db.select(db.transactions).get();
  });

  tearDown(() async => db.close());

  Future<String> cat(String name, {CategoryType type = CategoryType.expense}) async =>
      (await categories.findByName(name, type))!.id;

  Future<void> seed() async {
    final food = await cat('餐饮');
    final takeout = await categories.ensure(
      name: '外卖',
      type: CategoryType.expense,
      parentId: food,
    );
    final shopping = await cat('购物');
    final salary = await cat('工资', type: CategoryType.income);
    final wallet = (await accounts.all()).first;

    Future<void> add({
      required EntryType type,
      required int cents,
      required String categoryId,
      required DateTime at,
      String note = '',
      String? accountId,
      List<String> tags = const [],
    }) =>
        repo.create(
          NewTransaction(
            type: type,
            amountCents: cents,
            categoryId: categoryId,
            happenedAt: at,
            note: note,
            accountId: accountId,
            tags: tags,
          ),
        );

    await add(
      type: EntryType.expense,
      cents: 3850,
      categoryId: food,
      at: DateTime(2026, 10, 17, 12),
      note: '牛肉面',
      accountId: wallet.id,
      tags: ['出差'],
    );
    await add(
      type: EntryType.expense,
      cents: 23600,
      categoryId: shopping,
      at: DateTime(2026, 10, 1, 19),
      note: '超市采购',
    );
    await add(
      type: EntryType.expense,
      cents: 1500,
      categoryId: takeout.id,
      at: DateTime(2026, 8, 20, 12),
      note: '麻辣烫',
    );
    await add(
      type: EntryType.expense,
      cents: 9900,
      categoryId: shopping,
      at: DateTime(2025, 12, 31, 23),
      note: '旧单',
    );
    await add(
      type: EntryType.income,
      cents: 1451900,
      categoryId: salary,
      at: DateTime(2026, 10, 10, 10),
      note: 'Starbucks 兼职',
    );
  }

  test('关键词匹配备注，大小写不敏感', () async {
    await seed();

    final byNote = await repo.searchLedger(
      const LedgerFilter(keyword: '超市'),
      now: now,
    );
    expect(byNote.matchedCount, 1);
    expect(byNote.groups.single.items.single.transaction.note, '超市采购');

    final byCase = await repo.searchLedger(
      const LedgerFilter(keyword: 'starbucks'),
      now: now,
    );
    expect(byCase.matchedCount, 1);
    expect(byCase.groups.single.items.single.transaction.note, contains('Starbucks'));
  });

  test('关键词匹配分类名、账户名与标签', () async {
    await seed();

    final byCategory = await repo.searchLedger(
      const LedgerFilter(keyword: '餐饮'),
      now: now,
    );
    // 「餐饮」命中一级分类本身 + 二级「外卖」的一笔
    expect(byCategory.matchedCount, 2);

    final byAccount = await repo.searchLedger(
      LedgerFilter(keyword: (await accounts.all()).first.name),
      now: now,
    );
    expect(byAccount.matchedCount, 1);

    final byTag = await repo.searchLedger(
      const LedgerFilter(keyword: '出差'),
      now: now,
    );
    expect(byTag.matchedCount, 1);
  });

  test('类型 + 时间范围组合', () async {
    await seed();

    final expensesThisMonth = await repo.searchLedger(
      const LedgerFilter(type: EntryType.expense, range: SearchRange.thisMonth),
      now: now,
    );
    expect(
      expensesThisMonth.groups.expand((g) => g.items).map((r) => r.transaction.note),
      unorderedEquals(['牛肉面', '超市采购']),
    );

    final lastThree = await repo.searchLedger(
      const LedgerFilter(range: SearchRange.lastThreeMonths),
      now: now,
    );
    // 8 月那笔在「近三个月」（8/9/10）里，2025-12-31 不在
    expect(
      lastThree.groups.expand((g) => g.items).map((r) => r.transaction.note),
      unorderedEquals(['牛肉面', '超市采购', '麻辣烫', 'Starbucks 兼职']),
    );
  });

  test('分类筛选包含子分类，金额区间可叠加', () async {
    await seed();
    final food = await cat('餐饮');

    final byCategory = await repo.searchLedger(
      LedgerFilter(categoryId: food),
      now: now,
    );
    expect(byCategory.matchedCount, 2, reason: '餐饮 + 餐饮/外卖');

    final byAmount = await repo.searchLedger(
      const LedgerFilter(minCents: 10000, maxCents: 30000),
      now: now,
    );
    expect(
      byAmount.groups.expand((g) => g.items).map((r) => r.transaction.note),
      unorderedEquals(['超市采购']),
    );
  });

  test('账户与标签筛选', () async {
    await seed();
    final wallet = (await accounts.all()).first;

    final byAccount = await repo.searchLedger(
      LedgerFilter(accountId: wallet.id),
      now: now,
    );
    expect(byAccount.matchedCount, 1);

    final byTag = await repo.searchLedger(
      const LedgerFilter(tag: '出差'),
      now: now,
    );
    expect(byTag.matchedCount, 1);
    expect(byTag.groups.single.items.single.transaction.note, '牛肉面');
  });

  test('互斥条件返回空结果', () async {
    await seed();

    final result = await repo.searchLedger(
      const LedgerFilter(type: EntryType.expense, keyword: 'Starbucks'),
      now: now,
    );
    expect(result.isEmpty, isTrue);
    expect(result.matchedCount, 0);
  });

  test('结果按日分组倒序，且带当天小计', () async {
    await seed();

    final result = await repo.searchLedger(
      const LedgerFilter(range: SearchRange.thisMonth),
      now: now,
    );
    expect(result.groups.first.date, DateTime(2026, 10, 17));
    expect(result.groups.first.expenseCents, 3850);
  });

  test('超过上限时标记 truncated 并只返回上限条数', () async {
    final food = await cat('餐饮');
    for (var i = 0; i < 5; i++) {
      await repo.create(
        NewTransaction(
          type: EntryType.expense,
          amountCents: 100 + i,
          categoryId: food,
          happenedAt: DateTime(2026, 10, 17, 9),
          note: '第$i笔',
        ),
      );
    }

    final limited = await repo.searchLedger(
      const LedgerFilter(),
      limit: 3,
      now: now,
    );
    expect(limited.truncated, isTrue);
    expect(
      limited.groups.fold<int>(0, (sum, g) => sum + g.items.length),
      3,
    );

    final full = await repo.searchLedger(
      const LedgerFilter(),
      limit: 10,
      now: now,
    );
    expect(full.truncated, isFalse);
    expect(
      full.groups.fold<int>(0, (sum, g) => sum + g.items.length),
      5,
    );
  });

  test('关键词能搜到超出 limit 的老账（SQL 预筛）', () async {
    final food = await cat('餐饮');
    for (var i = 0; i < 30; i++) {
      await repo.create(
        NewTransaction(
          type: EntryType.expense,
          amountCents: 100 + i,
          categoryId: food,
          happenedAt: DateTime(2026, 1, 1, 9),
          note: '老账 $i',
        ),
      );
    }
    for (var i = 0; i < 30; i++) {
      await repo.create(
        NewTransaction(
          type: EntryType.expense,
          amountCents: 200 + i,
          categoryId: food,
          happenedAt: DateTime(2026, 10, 17, 9),
          note: '新账 $i',
        ),
      );
    }

    // limit 只取最近 5 笔，但关键词命中的是最早那批
    final result = await repo.searchLedger(
      const LedgerFilter(keyword: '老账 3'),
      limit: 5,
      now: now,
    );

    expect(result.matchedCount, 1, reason: '「老账 3」在最早的 30 笔里');
    expect(result.truncated, isFalse);
    expect(result.groups.single.items.single.transaction.note, '老账 3');
  });
}