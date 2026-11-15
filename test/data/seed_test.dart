import 'package:bean_count/data/category_library.dart';
import 'package:bean_count/data/db/app_database.dart';
import 'package:bean_count/data/db/connection.dart';
import 'package:bean_count/data/db/enums.dart';
import 'package:bean_count/data/seed.dart';
import 'package:drift/drift.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('首次建库写入分类库全集（支出 14 一级 + 44 二级 / 收入 7）与 1 个默认账户', () async {
    final db = AppDatabase(openInMemoryConnection());
    addTearDown(db.close);

    final categories = await db.select(db.categories).get();
    expect(categories, hasLength(65));
    expect(
      categories.where((c) => c.type == CategoryType.expense),
      hasLength(58),
    );
    expect(
      categories.where((c) => c.type == CategoryType.income),
      hasLength(7),
    );

    // 收入分类里必须有「工资」——导入真实数据时依赖它做同名复用。
    expect(
      categories.any(
        (c) => c.type == CategoryType.income && c.name == '工资',
      ),
      isTrue,
    );

    final accounts = await db.select(db.accounts).get();
    expect(accounts, hasLength(1));
    expect(accounts.single.id, kDefaultAccountId);
    expect(accounts.single.initialBalanceCents, 0);
  });

  test('重复播种不会产生重复行', () async {
    final db = AppDatabase(openInMemoryConnection());
    addTearDown(db.close);

    await seedDefaults(db);
    await seedDefaults(db);
    await seedCategoryLibrary(db);
    await seedCategoryLibrary(db);

    expect(await db.select(db.categories).get(), hasLength(65));
    expect(await db.select(db.accounts).get(), hasLength(1));
  });

  test('种子分类的 id、名称、颜色、图标一一对齐', () async {
    final ids = kSeedCategories.map((c) => c.id).toSet();
    expect(ids, hasLength(kSeedCategories.length), reason: 'id 必须唯一');

    for (final c in kSeedCategories) {
      expect(c.name, isNotEmpty);
      expect(c.iconKey, isNotEmpty);
      expect(c.color & 0xFF000000, 0xFF000000, reason: '颜色必须完全不透明');
    }

    // 支出分类的顺序就是设计色板的顺序，不能乱。
    for (var i = 0; i < kSeedExpenseCategories.length; i++) {
      expect(kSeedExpenseCategories[i].sortOrder, i);
    }
  });

  group('分类库落库', () {
    test('支出是 14 个一级 + 44 个二级', () async {
      final db = AppDatabase(openInMemoryConnection());
      addTearDown(db.close);

      final expense = (await db.select(db.categories).get())
          .where((c) => c.type == CategoryType.expense)
          .toList();
      final roots = expense.where((c) => c.parentId == null).toList();
      final children = expense.where((c) => c.parentId != null).toList();

      expect(roots, hasLength(14));
      expect(children, hasLength(44));
      expect(
        roots.map((c) => c.name),
        containsAll(<String>['餐饮', '交通', '通讯', '人情', '数码', '运动']),
      );

      final restaurant = roots.firstWhere((c) => c.name == '餐饮');
      final restaurantChildren = children
          .where((c) => c.parentId == restaurant.id)
          .map((c) => c.name)
          .toSet();
      expect(
        restaurantChildren,
        containsAll(<String>['早餐', '午餐', '晚餐', '外卖', '咖啡奶茶', '零食', '买菜']),
      );
    });

    test('账本里本来就是一级的不再挂成二级', () async {
      final plan = librarySeedRoots();
      final all = {
        for (final root in plan)
          root.name: root.children.map((c) => c.name).toSet(),
      };
      expect(all['购物'], isNot(contains('数码电器')));
      expect(all['医疗'], isNot(contains('健身运动')));
    });

    test('二级沿用父级颜色', () async {
      final db = AppDatabase(openInMemoryConnection());
      addTearDown(db.close);

      final rows = await db.select(db.categories).get();
      final byId = {for (final row in rows) row.id: row};
      for (final row in rows) {
        if (row.parentId == null) continue;
        expect(
          row.color,
          byId[row.parentId]!.color,
          reason: '「${row.name}」应与父级同色',
        );
      }
    });

    test('老账本升级补齐而不动已有分类', () async {
      final db = AppDatabase(openInMemoryConnection());
      addTearDown(db.close);

      // 退回「只有 12 个一级 + 6 个收入」的老账本状态，并给「打车」改个名
      final before = await db.select(db.categories).get();
      final roots = before
          .where((c) => c.parentId == null && c.type == CategoryType.expense)
          .toList();
      final snapshot = {
        for (final row in roots) row.name: (row.id, row.color, row.icon),
      };

      await (db.delete(db.categories)..where((t) => t.parentId.isNotNull()))
          .go();
      await (db.delete(db.categories)
            ..where((t) => t.name.equals('通讯') | t.name.equals('人情') | t.name.equals('报销')))
          .go();
      await (db.delete(db.appState)
            ..where((t) => t.key.equals('category_library_seed_v1')))
          .go();

      await seedCategoryLibrary(db);

      final after = await db.select(db.categories).get();
      final rootsAfter = after
          .where((c) => c.parentId == null && c.type == CategoryType.expense)
          .toList();
      // 已有一级的 id / 颜色 / 图标一字不动，也没有被复制
      for (final entry in snapshot.entries) {
        if (entry.key == '通讯' || entry.key == '人情') continue;
        final hit = rootsAfter.where((c) => c.name == entry.key);
        expect(hit, hasLength(1), reason: '「${entry.key}」不该被复制或改名');
        expect(hit.single.id, entry.value.$1);
        expect(hit.single.color, entry.value.$2);
        expect(hit.single.icon, entry.value.$3);
      }
      expect(rootsAfter, hasLength(14));
      expect(after.where((c) => c.parentId != null), hasLength(44));
      // 收入侧补上「报销」，其余收入分类不动
      expect(
        after.where((c) => c.type == CategoryType.income && c.name == '报销'),
        hasLength(1),
      );
    });

    test('落过一次之后不再运行，用户改名不会被重新补出来', () async {
      final db = AppDatabase(openInMemoryConnection());
      addTearDown(db.close);

      final taxi = (await db.select(db.categories).get())
          .firstWhere((c) => c.name == '打车');
      await (db.update(db.categories)..where((t) => t.id.equals(taxi.id)))
          .write(const CategoriesCompanion(name: Value('出租车')));

      await seedCategoryLibrary(db);

      final names = (await db.select(db.categories).get()).map((c) => c.name);
      expect(names, isNot(contains('打车')));
      expect(names.where((n) => n == '出租车'), hasLength(1));
    });
  });
}

