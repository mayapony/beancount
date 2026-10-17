import 'package:bean_count/data/db/app_database.dart';
import 'package:bean_count/data/db/connection.dart';
import 'package:bean_count/data/db/enums.dart';
import 'package:bean_count/data/repositories/category_repository.dart';
import 'package:bean_count/data/repositories/transaction_repository.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late AppDatabase db;
  late TransactionRepository transactions;
  late CategoryRepository categories;

  setUp(() async {
    db = AppDatabase(openInMemoryConnection());
    transactions = TransactionRepository(db);
    categories = CategoryRepository(db);
    await db.select(db.categories).get();
  });

  tearDown(() async => db.close());

  Future<Category> food() async =>
      (await categories.findByName('餐饮', CategoryType.expense))!;
  Future<Category> transport() async =>
      (await categories.findByName('交通', CategoryType.expense))!;

  Future<String> childOf(Category parent, String name) async =>
      (await categories.ensure(name: name, type: CategoryType.expense, parentId: parent.id)).id;

  test('含二级分类，合计只算支出', () async {
    final eat = await food();
    final takeaway = await childOf(eat, '外卖');
    final bus = await transport();

    await transactions.create(
      NewTransaction(
        type: EntryType.expense,
        amountCents: 3850,
        categoryId: eat.id,
        happenedAt: DateTime(2026, 10, 17, 12),
        note: '堂食',
      ),
    );
    await transactions.create(
      NewTransaction(
        type: EntryType.expense,
        amountCents: 2500,
        categoryId: takeaway,
        happenedAt: DateTime(2026, 10, 16, 12),
        note: '外卖',
      ),
    );
    await transactions.create(
      NewTransaction(
        type: EntryType.expense,
        amountCents: 1200,
        categoryId: bus.id,
        happenedAt: DateTime(2026, 10, 15, 12),
        note: '公交',
      ),
    );

    final ledger = await transactions.categoryLedger(eat.id);
    expect(ledger.count, 2, reason: '含子分类，不含交通');
    expect(ledger.totalCents, 6350);
    expect(ledger.groups, hasLength(2));
    expect(
      ledger.groups.expand((g) => g.items).map((r) => r.transaction.note).toSet(),
      {'堂食', '外卖'},
    );
  });

  test('from/to 是左闭右开', () async {
    final eat = await food();
    for (final day in [1, 15, 31]) {
      await transactions.create(
        NewTransaction(
          type: EntryType.expense,
          amountCents: 1000,
          categoryId: eat.id,
          happenedAt: DateTime(2026, 10, day, 12),
          note: 'd$day',
        ),
      );
    }

    final october = await transactions.categoryLedger(
      eat.id,
      from: DateTime(2026, 10),
      to: DateTime(2026, 11),
    );
    expect(october.count, 3);

    final firstHalf = await transactions.categoryLedger(
      eat.id,
      from: DateTime(2026, 10, 1),
      to: DateTime(2026, 10, 16),
    );
    expect(firstHalf.count, 2, reason: '1 号与 15 号，不含 31 号');
  });

  test('空分类返回空结果', () async {
    final eat = await food();
    final ledger = await transactions.categoryLedger(eat.id);
    expect(ledger.isEmpty, isTrue);
    expect(ledger.groups, isEmpty);
    expect(ledger.totalCents, 0);
  });

  test('超过 limit 只取最近 N 笔', () async {
    final eat = await food();
    for (var i = 0; i < 20; i++) {
      await transactions.create(
        NewTransaction(
          type: EntryType.expense,
          amountCents: 100 + i,
          categoryId: eat.id,
          happenedAt: DateTime(2026, 10, 1, 0, i),
          note: '第$i笔',
        ),
      );
    }

    final limited = await transactions.categoryLedger(eat.id, limit: 5);
    expect(limited.count, 5);
    expect(
      limited.totalCents,
      greaterThan(0),
      reason: '合计基于返回的那 5 笔',
    );
    expect(
      limited.groups.expand((g) => g.items).every((r) => r.transaction.happenedAt.day == 1),
      isTrue,
    );
  });
}
