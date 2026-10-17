# Tasks

## 1. 数据与仓储

- [x] 1.1 accounts 加 `billingDay` / `dueDay`（可空），`schemaVersion = 4` + 迁移；`test/data/db_migration_test.dart` 用例：v1→v4 与 v3→v4 都能开、老数据不变
- [x] 1.2 `AccountRepository` 透传两列；`create/update` 校验 1–28（越界抛 ArgumentError）；用例：保存后可读回、越界被拒、非信用卡不影响
- [x] 1.3 `dueReminders({now})`：只取信用卡+有还款日+有欠款，算下次还款日与天数，按天数升序；`test/data/card_due_test.dart` 用例：本月未到/今天/本月已过跨月、已还清不出现、多卡排序

## 2. 界面

- [x] 2.1 资产页顶部「待还」提醒卡（账户名、应还金额、还有 N 天/今天到期/已逾期 N 天，≤3 天用警示色）；`test/pages/assets_page_test.dart` 或新用例：有提醒时显示、无提醒时不显示
- [x] 2.2 账户编辑页：信用卡类型下出现「账单日/还款日」（1–28，可留空），其它类型隐藏；用例：信用卡显示、储蓄卡不显示、越界提示
- [x] 2.3 `flutter analyze` 干净、`flutter test` 全绿（不低于 270 + 新增）

## 3. 回归

- [x] 3.1 设备端回归：建一张信用卡账户、设还款日 → 记一笔支出 → 资产页出现「待还」与天数；结果写入 tasks.md

## 验证记录（2026-10-18）

- `flutter analyze`：No issues found；`flutter test`：**283 通过**（上一轮 270 + 本次 13）
- 设备端 `integration_test/card_bills_flow_test.dart -d emulator-5554`：通过
  - 建信用卡（账单日 5 / 还款日 20）→ 刷 3,200 元 → 资产页出现「待还 / 招商信用卡 / ¥3,200.00 / 还有 N 天」
- 迁移：`schemaVersion` 3 → 4 只给 accounts 加两列；v1→v4 与全新建库两条用例都过，老数据与索引不变
- 过程中修的展示问题：提醒卡头部原本对单张卡重复显示天数（下面一行已有）→ 单张不再显示头部天数；
  另 `SectionTitle` 内部自带 `Expanded`，不能塞进带 `Spacer` 的 `Row`（会 `RenderFlex` 报错），改用普通 `Text`
## Workflow follow-up

- 归档 change：`openspec archive credit-card-bills --yes`
- 归档后回写 `docs/PRODUCT_PLAN.md` §8（M6 状态）与 §14
