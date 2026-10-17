import 'package:bean_count/data/db/app_database.dart';
import 'package:bean_count/data/db/connection.dart';
import 'package:bean_count/data/db/enums.dart';
import 'package:bean_count/data/seed.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('首次建库写入 18 个分类（支出 12 + 收入 6）与 1 个默认账户', () async {
    final db = AppDatabase(openInMemoryConnection());
    addTearDown(db.close);

    final categories = await db.select(db.categories).get();
    expect(categories, hasLength(18));
    expect(
      categories.where((c) => c.type == CategoryType.expense),
      hasLength(12),
    );
    expect(
      categories.where((c) => c.type == CategoryType.income),
      hasLength(6),
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

    expect(await db.select(db.categories).get(), hasLength(18));
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
}
