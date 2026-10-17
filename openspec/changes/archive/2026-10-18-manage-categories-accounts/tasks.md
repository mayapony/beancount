# Tasks

## 1. 分类仓储

- [x] 1.1 `rename` 增加同层级重名校验（`DuplicateCategoryNameException`），自身改名不误判；用例：同名被拒、不同父级同名允许
- [x] 1.2 新增 `updateAppearance(id, {color, icon})`；用例：改图标后读回一致
- [x] 1.3 新增 `moveBy(id, delta)`（同类型同级交换排序，重复 sortOrder 也能正确换位）；用例：上移/下移/边界不动
- [x] 1.4 新增 `usageCounts()` 一次查出「分类 id → 笔数」；用例：与逐类 `transactionCount` 结果一致
- [x] 1.5 新增 `migrateAndDelete(fromId, toId)`：事务内迁移交易再删分类（含无引用子分类）；用例：迁移后笔数不变、目标分类笔数增加、源分类消失

## 2. 账户仓储

- [x] 2.1 新增 `create({name, type, initialBalanceCents})`，同名抛 `DuplicateAccountNameException`，id 不与名称绑定；用例：创建并读回
- [x] 2.2 新增 `update(id, {name, type, initialBalanceCents})`，改名查重；用例：改类型/期初余额后 `withBalances` 的余额随之变化
- [x] 2.3 新增 `delete(id)` 与 `usageCount(id)`，有引用抛 `AccountInUseException`；用例：有引用被拒、无引用可删

## 3. 分类页

- [x] 3.1 `CategoriesPage`：支出/收入切换 + 一级/二级列表 + 每类笔数；`test/pages/categories_page_test.dart` 断言分组与计数
- [x] 3.2 新建分类面板（名称 + 图标 + 父分类）；用例：新建后出现在列表，且记账仓储能查到
- [x] 3.3 编辑面板：改名（重名提示）、改图标、上移/下移、保存后列表刷新；用例覆盖改名与上移
- [x] 3.4 删除：无引用直接删；有引用弹「迁移到…」，选择目标后迁移并删除；用例覆盖两条路径 + 取消不改动

## 4. 账户页

- [x] 4.1 `AccountsPage`：名称/类型/期初/当前余额/笔数；用例断言渲染
- [x] 4.2 新增与编辑面板（名称、类型、期初余额）；用例：改期初余额后当前余额变化
- [x] 4.3 删除：有引用提示笔数并拒绝，无引用可删；两个用例

## 5. 接线与回归

- [x] 5.1 设置页新增「分类」「账户」入口；用例：点开进入对应页
- [x] 5.2 `flutter analyze` 干净、`flutter test` 全绿（不低于 132 + 新增）
- [x] 5.3 设备端回归：新建分类/二级分类 → 记账 → 改名 → 迁移删除 → 新建账户 → 改期初余额 → 删除账户；结果写入 tasks.md

## 验证记录（2026-10-18）

- `flutter analyze`：No issues found
- `flutter test`：**154 通过**（上一轮 132 + 本次 22）
- `flutter test integration_test/taxonomy_flow_test.dart -d emulator-5554`：2 通过（真实文件库）
  - 分类：新建二级「外卖」→ 用它记一笔 → 「餐饮」改名「吃饭」→ 删除时迁移到「交通」→ 重开数据库确认改名与迁移都在、交易仍 1 笔
  - 账户：新建「支付宝」初始 1000 → 记 38.50 支出后余额 961.50 → 删除被拒（提示 1 笔）→ 期初改 2000 后余额 1,961.50 → 重开数据库初始余额仍是 2000
- 已知取舍：账户删除只拒绝、不提供迁移（迁移账户会改余额归属，属于记账操作）

## Workflow follow-up

- 归档 change：`openspec archive manage-categories-accounts --yes`
- 归档后回写 `docs/PRODUCT_PLAN.md` §8（M2 状态）与 §14（划掉该行）
