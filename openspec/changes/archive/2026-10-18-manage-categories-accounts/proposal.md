# Proposal

## Why

分类与账户是用户自己的数据，但至今只能靠导入或写死种子产生：想加一个「维修」分类、把「招商银行卡」的期初余额改对、删掉建错的账户——都没有入口。
仓储层其实早就具备增删改查与「被引用不可删」的约束，缺的只是界面，以及删除时真正的迁移动作。

## What Changes

- **分类管理页**：设置 →「分类」；按支出/收入切换，展示一级分类与其下的二级分类、每类的使用笔数。
- **分类增删改**：新增（可指定父分类，最多两级）、改名（同层级重名会被拒绝）、改图标、上移/下移排序。
- **删除带迁移**：分类被交易引用时，弹「迁移到…」选择目标分类，迁移后删除；无引用则直接删。子分类随父分类一起处理。
- **账户管理页**：设置 →「账户」；展示名称、类型、初始余额、当前余额与笔数。
- **账户增删改**：新增、改名、改类型、改初始余额；被交易引用的账户拒绝删除并说明笔数。
- 非目标：标签管理、分类合并、跨类型迁移（支出分类不能迁到收入分类）、批量操作。

## Capabilities

### New Capabilities

（无，本次是既有能力的行为补全。）

### Modified Capabilities

- `ledger-taxonomy`: 新增「分类管理界面」「账户管理界面」「重名拒绝」「排序」四条行为；并把既有「删除被引用分类时提供迁移」落实到可操作流程

## Impact

- `lib/data/repositories/category_repository.dart`：新增 `updateAppearance` / `moveBy` / `usageCounts` / `migrateAndDelete`；`rename` 增加同层级重名检查
- `lib/data/repositories/account_repository.dart`：新增 `create` / `update` / `delete` / `usageCount`（`AccountInUseException`）
- 新增 `lib/pages/categories_page.dart`、`lib/pages/accounts_page.dart`
- `lib/pages/settings_page.dart`：新增「分类」「账户」两个入口
- 测试：两个仓储的新用例、分类/账户页 widget 测试、删除迁移闭环
- 无新增依赖
