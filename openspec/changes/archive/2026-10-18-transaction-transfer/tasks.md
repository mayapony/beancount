# Tasks

## 1. 数据模型与迁移

- [x] 1.1 `EntryType` 增加 `transfer`；`Transactions.categoryId` 改可空、新增 `toAccountId`；`schemaVersion = 2` 并写 v1→v2 迁移（`TableMigration` + 索引重建）；`test/data/db_migration_test.dart`：构造 v1 库 → 打开新版 → 历史交易字段不变、两个索引仍存在、迁移后可写入转账
- [x] 1.2 `dedupeKeyFor` 增加可选 `toAccountId`（仅转账传入，其它路径字节不变）；用例：历史三字段键与旧公式一致、转账不同转入账户得到不同键

## 2. 仓储语义

- [x] 2.1 `NewTransaction`/`create` 支持转账：必须两端账户、两端不同、无需分类；用例：成功写入、同账户被拒、缺账户被拒
- [x] 2.2 明细分组：转账不计入 `expenseCents`/`incomeCents`；用例：只有转账的一天小计为 0，`LedgerSnapshot` 的总笔数含转账
- [x] 2.3 账户余额与笔数把转账算进两端；用例：转出减、转入加、两端笔数各 +1、净资产不变
- [x] 2.4 洞察排除转账；用例：分类占比与趋势只由收支构成
- [x] 2.5 `TransactionRow`/`exportRows`/`searchLedger` 对可空分类与转账适配（关键词匹配两端账户名、导出类型列写「转账」+ 转出/转入列）；用例各一条

## 3. 记账面板（转账模式）

- [x] 3.1 「转账」分段与「从 / 到」账户选择器（复用账户面板）；`test/widgets/quick_entry_sheet_test.dart` 用例：切到转账后分类网格消失、两个账户胶囊出现
- [x] 3.2 转账提交：草稿带 `isTransfer` 与两端账户；用例：提交的草稿字段正确，未选账户时不能提交
- [x] 3.3 编辑转账时预填两端与金额；用例：以转账草稿打开面板，切回支出时分类网格恢复

## 4. 明细、详情与搜索

- [x] 4.1 明细行：转账显示「A → B」与中性色金额；用例断言文案与不出现 +/−
- [x] 4.2 详情页：转账显示「从/到」两行、隐藏分类行，可编辑与删除；用例覆盖展示 + 删除后余额还原
- [x] 4.3 搜索：类型新增「转账」，关键词匹配两端账户名；用例覆盖「只看转账」与「按转入账户名命中」

## 5. 回归

- [x] 5.1 `flutter analyze` 干净、`flutter test` 全绿（不低于 169 + 新增）
- [x] 5.2 设备端回归：v1 数据升级不丢 → 记一笔转账 → 明细/账户余额正确 → 改金额 → 删除还原；结果写入 tasks.md

## 验证记录（2026-10-18）

- `flutter analyze`：No issues found
- `flutter test`：**185 通过**（上一轮 169 + 本次 16）
- 迁移测试 `test/data/db_migration_test.dart`：用 **v1 真实 DDL** 造老库（含数据与两个索引）→ 新代码打开 → 历史交易字段不变、索引仍在、`user_version = 2`、可写转账；另有一条「全新库直接建成 v2」
- `flutter test integration_test/transfer_flow_test.dart -d emulator-5554`：2 通过
  - **真实应用库**：设备上由旧版本创建的 v1 库，装上新版本后首次打开即迁移到 2，历史分类与账户保留
  - UI 全链路：金豆 → 转账 → 300 → 完成 → 明细出现「A → B / 300.00」（不带符号）→ 两端账户各 ±300、各记一笔 → 进详情删除 → 余额还原
- 说明：改金额走的是与「记一笔」同一个预填面板与 `update()`，面板预填与编辑路径已由 widget 用例覆盖（`编辑模式：以现值预填…`），设备端不再重复点数值

## Workflow follow-up

- 归档 change：`openspec archive transaction-transfer --yes`
- 归档后回写 `docs/PRODUCT_PLAN.md` §8（M3 → 完成）与 §14
