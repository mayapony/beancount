import 'package:drift/drift.dart' show Value;
import 'package:bean_count/data/db/app_database.dart';
import 'package:bean_count/data/db/connection.dart';
import 'package:bean_count/data/db/enums.dart';
import 'package:bean_count/data/repositories/category_repository.dart';
import 'package:bean_count/data/repositories/transaction_repository.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late AppDatabase db;
  late CategoryRepository repo;

  setUp(() async {
    db = AppDatabase(openInMemoryConnection());
    repo = CategoryRepository(db);
    // 触发建库 + 种子
    await db.select(db.categories).get();
  });

  tearDown(() async => db.close());

  test('种子分类可按名称与类型查到', () async {
    final food = await repo.findByName('餐饮', CategoryType.expense);
    expect(food, isNotNull);
    expect(food!.type, CategoryType.expense);

    final salary = await repo.findByName('工资', CategoryType.income);
    expect(salary, isNotNull);
    expect(salary!.type, CategoryType.income);
  });

  test('新增分类后立即可按名字查到，且同名只建一条', () async {
    final first = await repo.ensure(name: '维修', type: CategoryType.expense);
    final second = await repo.ensure(name: '维修', type: CategoryType.expense);

    expect(second.id, first.id);
    expect(await repo.all(CategoryType.expense), hasLength(13));
  });

  test('二级分类挂在父分类下，第三级被拒绝', () async {
    final food = await repo.findByName('餐饮', CategoryType.expense);

    final lunch = await repo.ensure(
      name: '午餐',
      type: CategoryType.expense,
      parentId: food!.id,
    );
    expect(lunch.parentId, food.id);
    expect(await repo.childrenOf(food.id), hasLength(1));

    await expectLater(
      repo.ensure(name: '商务午餐', type: CategoryType.expense, parentId: lunch.id),
      throwsA(isA<StateError>()),
    );
  });

  test('子分类类型必须与父分类一致', () async {
    final food = await repo.findByName('餐饮', CategoryType.expense);
    await expectLater(
      repo.ensure(name: '午餐', type: CategoryType.income, parentId: food!.id),
      throwsA(isA<ArgumentError>()),
    );
  });

  test('被交易引用的分类不可删除', () async {
    final food = await repo.findByName('餐饮', CategoryType.expense);
    await db.into(db.transactions).insert(
          TransactionsCompanion.insert(
            id: 'tx-1',
            type: EntryType.expense,
            amountCents: 3850,
            categoryId: Value(food!.id),
            happenedAt: DateTime(2026, 10, 17, 12, 30),
            dedupeKey: 'k1',
          ),
        );

    await expectLater(
      repo.delete(food.id),
      throwsA(isA<CategoryInUseException>()),
    );
  });

  test('未被引用的分类可删除，子分类一并删除', () async {
    final repair = await repo.ensure(name: '维修', type: CategoryType.expense);
    final sub = await repo.ensure(
      name: '家电维修',
      type: CategoryType.expense,
      parentId: repair.id,
    );

    await repo.delete(repair.id);

    expect(await repo.byId(repair.id), isNull);
    expect(await repo.byId(sub.id), isNull);
  });

  test('导入的分类按名字分配图标', () async {
    expect(CategoryRepository.iconForCategoryName('外卖'), 'delivery_dining');
    expect(CategoryRepository.iconForCategoryName('零食'), 'cookie');
    expect(CategoryRepository.iconForCategoryName('打车'), 'local_taxi');
    // 猜不到时退回「其他」，但聚餐这种带"餐"的能猜到餐厅
    expect(CategoryRepository.iconForCategoryName('聚餐'), 'restaurant');
    expect(CategoryRepository.iconForCategoryName('某个奇怪名字'), 'more_horiz');

    final created = await repo.ensure(name: '外卖', type: CategoryType.expense);
    expect(created.icon, 'delivery_dining');
  });

  test('新建分类一定有颜色与图标，且同名同类颜色稳定', () async {
    final a = await repo.ensure(name: '维修', type: CategoryType.expense);
    expect(a.color, isNot(0));
    expect(a.icon, isNotEmpty);

    final again = await repo.ensure(name: '维修', type: CategoryType.expense);
    expect(again.color, a.color);
  });

  test('改名：同层级重名被拒，不同父级可同名', () async {
    final food = await repo.findByName('餐饮', CategoryType.expense);
    final transport = await repo.findByName('交通', CategoryType.expense);
    final shopping = await repo.findByName('购物', CategoryType.expense);

    await expectLater(
      repo.rename(transport!.id, '餐饮'),
      throwsA(isA<DuplicateCategoryNameException>()),
    );
    expect((await repo.byId(transport.id))!.name, '交通');

    // 不同父级下的同名不冲突
    final lunch = await repo.ensure(
      name: '其他',
      type: CategoryType.expense,
      parentId: food!.id,
    );
    final snack = await repo.ensure(
      name: '其他',
      type: CategoryType.expense,
      parentId: shopping!.id,
    );
    await repo.rename(snack.id, '其他');
    expect(lunch.name, '其他');

    // 改回自己原来的名字不算冲突
    await repo.rename(food.id, '吃饭');
    expect((await repo.byId(food.id))!.name, '吃饭');
  });

  test('updateAppearance 只改图标与颜色', () async {
    final food = await repo.findByName('餐饮', CategoryType.expense);
    await repo.updateAppearance(food!.id, icon: 'restaurant', color: 0xFF123456);

    final updated = (await repo.byId(food.id))!;
    expect(updated.icon, 'restaurant');
    expect(updated.color, 0xFF123456);
    expect(updated.name, '餐饮');
  });

  test('moveBy 上移/下移交换排序，边界不动', () async {
    final before = await repo.roots(CategoryType.expense);
    final first = before.first;
    final second = before[1];

    await repo.moveBy(second.id, -1);
    var order =
        (await repo.roots(CategoryType.expense)).map((c) => c.id).toList();
    expect(order.take(2), [second.id, first.id]);

    await repo.moveBy(second.id, 1);
    order = (await repo.roots(CategoryType.expense)).map((c) => c.id).toList();
    expect(order.take(2), [first.id, second.id]);

    // 边界：第一个再上移不动
    await repo.moveBy(first.id, -1);
    order = (await repo.roots(CategoryType.expense)).map((c) => c.id).toList();
    expect(order.take(2), [first.id, second.id]);
  });

  test('moveBy 在 sortOrder 重复时也能换位', () async {
    final a = await repo.ensure(name: '甲', type: CategoryType.expense);
    final b = await repo.ensure(name: '乙', type: CategoryType.expense);
    // 人为制造重复排序号（历史数据可能这样）
    await db.customStatement(
      'UPDATE categories SET sort_order = 99 WHERE id IN (?, ?)',
      [a.id, b.id],
    );

    await repo.moveBy(b.id, -1);

    final order =
        (await repo.roots(CategoryType.expense)).map((c) => c.id).toList();
    expect(order.indexOf(b.id), lessThan(order.indexOf(a.id)));
  });

  test('usageCounts 与逐类计数一致', () async {
    final food = await repo.findByName('餐饮', CategoryType.expense);
    final transport = await repo.findByName('交通', CategoryType.expense);
    final transactions = TransactionRepository(db);
    for (final (cents, categoryId, note) in [
      (1000, food!.id, '一'),
      (2000, food.id, '二'),
      (3000, transport!.id, '三'),
    ]) {
      await transactions.create(
        NewTransaction(
          type: EntryType.expense,
          amountCents: cents,
          categoryId: categoryId,
          happenedAt: DateTime(2026, 10, 17, 9),
          note: note,
        ),
      );
    }

    final counts = await repo.usageCounts();
    expect(counts[food.id], 2);
    expect(counts[transport.id], 1);
    expect(counts[food.id], await repo.transactionCount(food.id));
  });

  test('migrateAndDelete 迁移交易后删除源分类与子分类', () async {
    final food = await repo.findByName('餐饮', CategoryType.expense);
    final lunch = await repo.ensure(
      name: '午餐',
      type: CategoryType.expense,
      parentId: food!.id,
    );
    final target = await repo.ensure(name: '吃饭', type: CategoryType.expense);
    final transactions = TransactionRepository(db);
    for (var i = 0; i < 3; i++) {
      await transactions.create(
        NewTransaction(
          type: EntryType.expense,
          amountCents: 1000 + i,
          categoryId: i == 2 ? lunch.id : food.id,
          happenedAt: DateTime(2026, 10, 17, 9 + i),
          note: '第$i笔',
        ),
      );
    }

    await repo.migrateAndDelete(food.id, target.id);

    expect(await repo.byId(food.id), isNull);
    expect(await repo.byId(lunch.id), isNull, reason: '子分类一并删除');
    expect(await transactions.count(), 3, reason: '交易一笔不少');
    expect(await repo.transactionCount(target.id), 3);
  });

  test('migrateAndDelete 拒绝跨类型与迁到自己的子级', () async {
    final food = await repo.findByName('餐饮', CategoryType.expense);
    final lunch = await repo.ensure(
      name: '午餐',
      type: CategoryType.expense,
      parentId: food!.id,
    );
    final salary = await repo.findByName('工资', CategoryType.income);

    await expectLater(
      repo.migrateAndDelete(food.id, salary!.id),
      throwsA(isA<ArgumentError>()),
    );
    await expectLater(
      repo.migrateAndDelete(food.id, lunch.id),
      throwsA(isA<ArgumentError>()),
    );
  });
}
