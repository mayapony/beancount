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
    await db.select(db.categories).get(); // 建库 + 种子
  });

  tearDown(() async => db.close());

  Future<void> seed({required bool auto, String note = ''}) async {
    final category = (await categories.all(CategoryType.expense)).first;
    await transactions.create(NewTransaction(
      type: EntryType.expense,
      amountCents: 1200,
      categoryId: category.id,
      happenedAt: DateTime(2026, 10, 18, 12),
      note: note,
      source: auto ? EntrySource.auto : EntrySource.manual,
    ));
  }

  test('recentAutoEntries 只返回 auto 来源，按时间倒序', () async {
    await seed(auto: false, note: '手动');
    await seed(auto: true, note: '自动 A');
    await seed(auto: true, note: '自动 B');

    final rows = await transactions.recentAutoEntries();
    expect(rows, hasLength(2));
    expect(rows.every((r) => r.transaction.source == EntrySource.auto), isTrue);
    // 倒序：最近的一笔在前
    expect(rows.first.transaction.note, '自动 B');
  });

  test('recentAutoEntries 无 auto 记录时返回空', () async {
    await seed(auto: false);
    expect(await transactions.recentAutoEntries(), isEmpty);
  });
}
