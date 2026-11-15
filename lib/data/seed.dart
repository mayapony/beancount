import 'package:drift/drift.dart';

import '../theme/category_icons.dart';
import '../theme/tokens.dart';
import '../utils/colors.dart';
import 'category_library.dart';
import 'db/app_database.dart';
import 'db/enums.dart';

/// 种子分类：12 个支出 + 6 个收入。
///
/// 为什么收入要单独一套：记录面板切到「收入」时如果复用支出分类，
/// 会出现"收入 · 餐饮"这种语义错误，也让导入的「工资」无处安放。
///
/// id、名称、图标三者按**下标对齐**，颜色直接取 `BeanColors`，
/// 保证"设计规范里的第 i 个分类"和"数据库里的种子"永远是同一个东西。
class SeedCategory {
  const SeedCategory({
    required this.id,
    required this.name,
    required this.type,
    required this.color,
    required this.iconKey,
    required this.sortOrder,
  });

  final String id;
  final String name;
  final CategoryType type;
  final int color;
  final String iconKey;
  final int sortOrder;
}

const _expenseIds = <String>[
  'cat-food',
  'cat-transport',
  'cat-shopping',
  'cat-entertainment',
  'cat-home',
  'cat-medical',
  'cat-education',
  'cat-travel',
  'cat-sport',
  'cat-digital',
  'cat-pet',
  'cat-other',
];

const _incomeIds = <String>[
  'cat-salary',
  'cat-bonus',
  'cat-parttime',
  'cat-invest',
  'cat-redpacket',
  'cat-other-income',
];

const _incomeNames = <String>['工资', '奖金', '兼职', '理财', '红包', '其他收入'];

/// 默认账户：初始余额一律为 0，余额完全由交易推导。
const kDefaultAccountId = 'acc-default';
const kDefaultAccountName = '默认账户';

final List<SeedCategory> kSeedExpenseCategories = <SeedCategory>[
  for (var i = 0; i < BeanColors.categoryNames.length; i++)
    SeedCategory(
      id: _expenseIds[i],
      name: BeanColors.categoryNames[i],
      type: CategoryType.expense,
      color: argbOf(BeanColors.categories[i]),
      iconKey: kExpenseCategoryIconKeys[i],
      sortOrder: i,
    ),
];

final List<SeedCategory> kSeedIncomeCategories = <SeedCategory>[
  for (var i = 0; i < _incomeNames.length; i++)
    SeedCategory(
      id: _incomeIds[i],
      name: _incomeNames[i],
      type: CategoryType.income,
      color: argbOf(BeanColors.incomeCategories[i]),
      iconKey: kIncomeCategoryIconKeys[i],
      sortOrder: i,
    ),
];

List<SeedCategory> get kSeedCategories => [
      ...kSeedExpenseCategories,
      ...kSeedIncomeCategories,
    ];

/// 写入默认数据。用固定 id + `insertOrIgnore` 保证幂等：
/// 重复调用（或用户删了某个种子分类后再启动）都不会产生重复行。
Future<void> seedDefaults(AppDatabase db) async {
  await db.batch((batch) {
    batch.insertAll(
      db.categories,
      [
        for (final c in kSeedCategories)
          CategoriesCompanion.insert(
            id: c.id,
            name: c.name,
            type: c.type,
            color: c.color,
            icon: c.iconKey,
            sortOrder: Value(c.sortOrder),
          ),
      ],
      mode: InsertMode.insertOrIgnore,
    );
    batch.insertAll(
      db.accounts,
      [
        AccountsCompanion.insert(
          id: kDefaultAccountId,
          name: kDefaultAccountName,
          type: const Value(AccountType.wallet),
          initialBalanceCents: const Value(0),
          sortOrder: const Value(0),
        ),
      ],
      mode: InsertMode.insertOrIgnore,
    );
  });
}

/// 分类库种子的完成标记：只在首次建库与 v7 升级时各跑一次。
///
/// 为什么需要标记：落库按「同一父级下同名即复用」判重，用户把「打车」改名成
/// 「出租车」之后再来一次种子，就会平白多出一个「打车」。
const _kLibrarySeedKey = 'category_library_seed_v1';

/// 把内置分类库落进账本：一级沿用已有分类，二级挂到它下面。
///
/// 空库首启（[seedDefaults] 之后）与老账本升级都会调用；已有分类的 id、名称、
/// 颜色、图标与排序一动不动，只补缺的那部分。
Future<void> seedCategoryLibrary(AppDatabase db) async {
  final seeded = await (db.select(db.appState)
        ..where((t) => t.key.equals(_kLibrarySeedKey)))
      .getSingleOrNull();
  if (seeded != null) return;

  final existing = await db.select(db.categories).get();
  final byKey = <String, Category>{
    for (final row in existing)
      _categoryKey(row.name, row.type, row.parentId): row,
  };
  final nextOrders = <String, int>{};

  int takeOrder(CategoryType type, String? parentId) {
    final key = '${type.name}|${parentId ?? ''}';
    final order = nextOrders.putIfAbsent(key, () {
      var max = -1;
      for (final row in existing) {
        if (row.type == type && row.parentId == parentId && row.sortOrder > max) {
          max = row.sortOrder;
        }
      }
      return max + 1;
    });
    nextOrders[key] = order + 1;
    return order;
  }

  Future<Category> ensureSeeded({
    required String name,
    required CategoryType type,
    required String iconKey,
    required int color,
    String? parentId,
  }) async {
    final key = _categoryKey(name, type, parentId);
    final hit = byKey[key];
    if (hit != null) return hit;
    final category = Category(
      id: 'cat-lib-${parentId == null ? '' : '$parentId-'}$name',
      name: name,
      type: type,
      parentId: parentId,
      color: color,
      icon: iconKey,
      sortOrder: takeOrder(type, parentId),
      createdAt: DateTime.now(),
    );
    await db.into(db.categories).insert(category);
    byKey[key] = category;
    existing.add(category);
    return category;
  }

  await db.transaction(() async {
    var paletteIndex = 0;
    for (final plan in librarySeedRoots()) {
      final root = await ensureSeeded(
        name: plan.name,
        type: CategoryType.expense,
        iconKey: plan.iconKey,
        color: plan.color != 0
            ? plan.color
            : argbOf(BeanColors.categories[paletteIndex++ % BeanColors.categories.length]),
      );
      for (final child in plan.children) {
        await ensureSeeded(
          name: child.name,
          type: CategoryType.expense,
          iconKey: child.iconKey,
          // 二级沿用父级色：网格里同一簇颜色一致，扫一眼就知道属于谁
          color: root.color,          parentId: root.id,
        );
      }
    }
    for (final entry in libraryIncomeSeeds.entries) {
      await ensureSeeded(
        name: entry.key,
        type: CategoryType.income,
        iconKey: entry.value,
        color: argbOf(BeanColors.incomeCategories.first),
      );
    }
    await db.into(db.appState).insertOnConflictUpdate(
          AppStateCompanion.insert(key: _kLibrarySeedKey, value: '1'),
        );
  });
}

String _categoryKey(String name, CategoryType type, String? parentId) =>
    '${type.name}|${parentId ?? ''}|${name.trim()}';

