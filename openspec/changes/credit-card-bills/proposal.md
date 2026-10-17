# Proposal

## Why

资产页能告诉你「这张信用卡欠了 3,200」，但最有用的那条信息没有：**什么时候要还**。
M6 里「信用卡还款提醒」缺的就是这个——按账单日/还款日算出「下个还款日 + 还剩几天 + 要还多少」，放在资产页最显眼的位置。

## What Changes

- **账户上加两个日子**：账单日 `billingDay`、还款日 `dueDay`（1–28，可空）。只在信用卡上有意义，其它类型不显示。
- **还款提醒卡**：资产页顶部出现「待还」卡片，列出每张信用卡的应还金额与「还有 N 天 / 今天到期 / 已逾期 N 天」，按紧急程度排序。
- **日期推算规则**：还款日只到 1–28（避开大小月与 2 月），所以「下一个还款日」总是本月或下月的这一天；今天正好是还款日算「今天到期」，过了算逾期。
- **数据迁移**：`schemaVersion` 3 → 4，只给 accounts 加两列（可空），不动既有数据。
- 非目标：分期/最低还款额、自动生成还款交易、跨账户账单汇总（一家银行多张卡）、推送通知（本地通知是另一个量级）。

## Capabilities

### New Capabilities

- `card-bills`: 信用卡账单日/还款日的设置、下次还款日与应还金额的推算、资产页提醒卡

### Modified Capabilities

（无：账户余额与统计口径不变，只是多了两个日期字段与一个提示。）

## Impact

- `lib/data/db/app_database.dart`：accounts 加 `billingDay` / `dueDay`，`schemaVersion = 4` + 迁移
- `lib/data/repositories/account_repository.dart`：字段透传 + `dueReminders()`（算下次还款日、剩余天数、应还）
- `lib/pages/assets_page.dart`：顶部提醒卡
- `lib/pages/accounts_page.dart`：信用卡可编辑账单日/还款日
- 测试：日期推算（含边界）、迁移、仓储、提醒卡、设备端
