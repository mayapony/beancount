# Proposal

## Why

每月固定的那几笔——房租、工资、宽带、会员——现在只能到日子手动记。忘了就漏，记晚了金额对不上，
而"循环交易"是 PRODUCT_PLAN 里 M4 的第一项，也是记账 App 从"能记"走向"少动手"的关键一步。

## What Changes

- **循环规则**：新建一条规则（支出 / 收入 / 转账三选一、金额、分类或两端账户、备注、每月几号、生效起始月）。
  每月固定日支持 1–28 与「月末」（29/30/31 号统一落到当月最后一天）。
- **自动补记**：App 打开时执行一次「到期扫描」，把从上次执行到现在所有应发生的期数补记成真实交易；
  同一条规则同一期只补一次（即使改过规则、换过设备也不会重复）。
- **规则管理**：设置 →「循环记账」，列出全部规则（下次执行日、是否启用），可新建、编辑、暂停、删除。
- **备注历史**：记一笔的备注弹窗里给出「最近用过」的备注，点一下就填上；数据来自真实历史，不用维护词表。
- 非目标：后台/系统级定时（不做 WorkManager，采用"打开即补"）、每周/每年频率、按规则自动改历史、多规则合并。

## Capabilities

### New Capabilities

- `ledger-recurring`: 周期性记账规则的增删改查、到期补记（幂等）与规则管理界面
- `ledger-notes`: 记账时复用历史备注（最近备注建议）

### Modified Capabilities

（无：交易本身的存储与语义不变，循环规则只是"批量生成交易"的上游。）

## Impact

- `lib/data/db/app_database.dart`：新增 `recurring_rules` 表，`schemaVersion = 3`，v2→v3 迁移（建表）
- 新增 `lib/data/repositories/recurring_repository.dart`、`lib/services/recurring/recurring_service.dart`
- `lib/pages/settings_page.dart`：新增「循环记账」入口；新增 `lib/pages/recurring_page.dart`
- `lib/widgets/quick_entry_sheet.dart`：备注弹窗加「最近用过」
- `lib/pages/shell.dart`：启动时执行一次补记
- 测试：迁移、规则日期计算（含月末）、补记幂等、页面与面板用例、设备端回归
- 无新增依赖
