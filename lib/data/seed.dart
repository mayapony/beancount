import 'package:drift/drift.dart';

import '../theme/category_icons.dart';
import '../theme/tokens.dart';
import '../utils/colors.dart';
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
