# Proposal

## Why

账户之间挪钱（工资卡→支付宝、信用卡还款）现在只能记成一笔支出 + 一笔收入，结果是：收支统计被虚增两遍，明细里出现两条互不相关的记录，账户余额还未必对得上。
M3「记账核心」的验收项里，转账是最后一个没做的——也是唯一一个**记错就会污染全部统计**的。

## What Changes

- **数据模型**：交易新增 `transfer` 类型；`categoryId` 变为可空（转账没有分类）；新增 `toAccountId`（转入账户）。数据库版本 1 → 2，带真实迁移（不丢数据）。
- **记账面板**：支出/收入之外新增「转账」分段；选中后分类网格换成「从 / 到」两个账户选择器，金额与备注沿用现有键盘与备注行。
- **余额语义**：转账让转出账户减、转入账户加；**不计入收入、不计入支出**，所有收支合计、日均、洞察图表都不含转账。
- **明细与详情**：转账行显示「账户 A → 账户 B」，用中性色金额（不带 +/− 号与收支色）；详情页同样展示两端口，可编辑、可删除。
- **搜索**：类型筛选增加「转账」；关键词匹配两个账户名。
- **导入**：BeeCount 导入仍跳过转账行（现状不变），文档里写明原因。
- 非目标：跨币种转账、手续费、多笔批量转账、转账模板。

## Capabilities

### New Capabilities

- `ledger-transfers`: 账户之间的资金移动：记账入口、余额影响、统计排除、展示与编辑删除

### Modified Capabilities

（无：`ledger-storage` 的存储语义不变，`ledger-editing` 的编辑删除入口对转账同样适用。）

## Impact

- `lib/data/db/app_database.dart`：`EntryType.transfer`、`categoryId` 可空、新增 `toAccountId`、`schemaVersion = 2` 与 v1→v2 迁移
- `lib/data/db/enums.dart`：`EntryType.transfer`
- `lib/data/dedupe.dart`：转账把转入账户纳入去重键（其余情形键值不变，历史数据不需要重算）
- `lib/data/repositories/*`：交易创建/明细分组/账户余额/搜索/导出对转账的适配
- `lib/widgets/quick_entry_sheet.dart`：转账模式
- `lib/widgets/ledger_day_list.dart`、`lib/pages/transaction_detail_page.dart`、`lib/pages/search_page.dart`：转账展示
- 测试：迁移测试、仓储语义测试、面板与详情 widget 测试、设备端回归
- 无新增依赖
