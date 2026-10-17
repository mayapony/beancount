import 'package:bean_count/data/db/app_database.dart';
import 'package:bean_count/data/db/connection.dart';
import 'package:bean_count/data/db/enums.dart';
import 'package:bean_count/data/dedupe.dart';
import 'package:bean_count/data/repositories/category_repository.dart';
import 'package:bean_count/data/repositories/transaction_repository.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late AppDatabase db;
  late TransactionRepository repo;
  late CategoryRepository categories;

  setUp(() async {
    db = AppDatabase(openInMemoryConnection());
    repo = TransactionRepository(db);
    categories = CategoryRepository(db);
    await db.select(db.transactions).get(); // 触发建库 + 种子
  });

  tearDown(() async => db.close());

  Future<String> foodId() async =>
      (await categories.findByName('餐饮', CategoryType.expense))!.id;

  test('38.5 元以 3850 分落库', () async {
    final result = await repo.create(
      NewTransaction(
        type: EntryType.expense,
        amountCents: 3850,
        categoryId: await foodId(),
        happenedAt: DateTime(2026, 10, 17, 12, 30),
        note: '午餐',
      ),
    );

    expect(result.inserted, isTrue);
    final row = await (db.select(db.transactions)
          ..where((t) => t.id.equals(result.transactionId)))
        .getSingle();
    expect(row.amountCents, 3850);
    expect(row.note, '午餐');
  });

  test('同时间同金额同备注的第二次写入被拒绝', () async {
    final at = DateTime(2026, 10, 17, 12, 30);
    final first = await repo.create(
      NewTransaction(
        type: EntryType.expense,
        amountCents: 3850,
        categoryId: await foodId(),
        happenedAt: at,
        note: '聚餐  ',
      ),
    );
    final second = await repo.create(
      NewTransaction(
        type: EntryType.expense,
        amountCents: 3850,
        categoryId: await foodId(),
        happenedAt: at,
        note: '聚餐',
      ),
    );

    expect(first.inserted, isTrue);
    expect(second.inserted, isFalse);
    expect(second.transactionId, first.transactionId);
    expect(await repo.count(), 1);
  });

  test('不同备注、不同金额、不同时间都可写入', () async {
    final at = DateTime(2026, 10, 17, 12, 30);
    final category = await foodId();

    for (final (amount, note, time) in [
      (3850, '午餐', at),
      (3850, '晚餐', at),
      (3900, '午餐', at),
      (3850, '午餐', at.add(const Duration(minutes: 1))),
    ]) {
      final r = await repo.create(
        NewTransaction(
          type: EntryType.expense,
          amountCents: amount,
          categoryId: category,
          happenedAt: time,
          note: note,
        ),
      );
      expect(r.inserted, isTrue, reason: '$amount / $note / $time');
    }
    expect(await repo.count(), 4);
  });

  test('备注为空也能去重', () async {
    final at = DateTime(2026, 10, 17, 8);
    final category = await foodId();
    final a = await repo.create(
      NewTransaction(
        type: EntryType.expense,
        amountCents: 1200,
        categoryId: category,
        happenedAt: at,
      ),
    );
    final b = await repo.create(
      NewTransaction(
        type: EntryType.expense,
        amountCents: 1200,
        categoryId: category,
        happenedAt: at,
      ),
    );
    expect(a.inserted, isTrue);
    expect(b.inserted, isFalse);
  });

  test('标签自动创建且同名复用', () async {
    final category = await foodId();
    await repo.create(
      NewTransaction(
        type: EntryType.expense,
        amountCents: 1000,
        categoryId: category,
        happenedAt: DateTime(2026, 10, 17, 9),
        note: 'A',
        tags: ['报销', '出差'],
      ),
    );
    await repo.create(
      NewTransaction(
        type: EntryType.expense,
        amountCents: 2000,
        categoryId: category,
        happenedAt: DateTime(2026, 10, 17, 10),
        note: 'B',
        tags: ['报销'],
      ),
    );

    final tags = await db.select(db.tags).get();
    expect(tags.map((t) => t.name).toSet(), {'报销', '出差'});
    expect(await db.select(db.transactionTags).get(), hasLength(3));
  });

  test('按天分组倒序、支出小计正确', () async {
    final category = await foodId();
    await repo.create(
      NewTransaction(
        type: EntryType.expense,
        amountCents: 1000,
        categoryId: category,
        happenedAt: DateTime(2026, 10, 17, 9),
        note: '早',
      ),
    );
    await repo.create(
      NewTransaction(
        type: EntryType.expense,
        amountCents: 2000,
        categoryId: category,
        happenedAt: DateTime(2026, 10, 17, 12),
        note: '午',
      ),
    );
    await repo.create(
      NewTransaction(
        type: EntryType.income,
        amountCents: 500000,
        categoryId: (await categories.findByName('工资', CategoryType.income))!.id,
        happenedAt: DateTime(2026, 10, 16, 12),
        note: '工资',
      ),
    );

    final groups = await repo.dayGroups();
    expect(groups, hasLength(2));
    expect(groups.first.date, DateTime(2026, 10, 17));
    expect(groups.first.expenseCents, 3000);
    expect(groups.first.items.first.amountCents, 2000, reason: '组内按时间倒序');
    expect(groups.last.incomeCents, 500000);
  });

  test('去重键跨次计算稳定，且时间精确到秒', () {
    final a = dedupeKeyFor(
      happenedAt: DateTime(2026, 10, 17, 12, 30, 0),
      amountCents: 3850,
      note: '聚餐',
    );
    final b = dedupeKeyFor(
      happenedAt: DateTime(2026, 10, 17, 12, 30, 0, 999),
      amountCents: 3850,
      note: ' 聚餐 ',
    );
    expect(a, b);
    expect(a, hasLength(16));

    final c = dedupeKeyFor(
      happenedAt: DateTime(2026, 10, 17, 12, 30, 1),
      amountCents: 3850,
      note: '聚餐',
    );
    expect(c, isNot(a));
  });
}
