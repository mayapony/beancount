import 'package:bean_count/data/db/app_database.dart';
import 'package:bean_count/data/db/connection.dart';
import 'package:bean_count/data/repositories/app_state_repository.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late AppDatabase db;
  late AppStateRepository repo;

  setUp(() async {
    db = AppDatabase(openInMemoryConnection());
    repo = AppStateRepository(db);
    await db.select(db.appState).get(); // 触发建库
  });

  tearDown(() async => db.close());

  test('写入后能原样读回，重复写覆盖旧值', () async {
    await repo.write(AppStateRepository.kLastCategoryId, 'cat-food');
    expect(await repo.read(AppStateRepository.kLastCategoryId), 'cat-food');

    await repo.write(AppStateRepository.kLastCategoryId, 'cat-shopping');
    expect(await repo.read(AppStateRepository.kLastCategoryId), 'cat-shopping');
    expect(await db.select(db.appState).get(), hasLength(1));
  });

  test('上次选择整体存取', () async {
    await repo.saveSelection(
      const LastEntrySelection(
        categoryId: 'cat-salary',
        accountId: 'acc-cmb',
        isIncome: true,
      ),
    );

    final loaded = await repo.lastSelection();
    expect(loaded.categoryId, 'cat-salary');
    expect(loaded.accountId, 'acc-cmb');
    expect(loaded.isIncome, isTrue);
  });

  test('没有历史时返回空选择', () async {
    final loaded = await repo.lastSelection();
    expect(loaded.categoryId, isNull);
    expect(loaded.accountId, isNull);
    expect(loaded.isIncome, isFalse);
  });
}
