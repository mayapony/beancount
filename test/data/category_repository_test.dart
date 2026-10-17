import 'package:bean_count/data/db/app_database.dart';
import 'package:bean_count/data/db/connection.dart';
import 'package:bean_count/data/db/enums.dart';
import 'package:bean_count/data/repositories/category_repository.dart';
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
            categoryId: food!.id,
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
}
