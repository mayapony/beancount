# Tasks

## 1. 数据与仓储

- [ ] 1.1 accounts 加 `billingDay` / `dueDay`（可空），`schemaVersion = 4` + 迁移；`test/data/db_migration_test.dart` 用例：v1→v4 与 v3→v4 都能开、老数据不变
- [ ] 1.2 `AccountRepository` 透传两列；`create/update` 校验 1–28（越界抛 ArgumentError）；用例：保存后可读回、越界被拒、非信用卡不影响
- [ ] 1.3 `dueReminders({now})`：只取信用卡+有还款日+有欠款，算下次还款日与天数，按天数升序；`test/data/card_due_test.dart` 用例：本月未到/今天/本月已过跨月、已还清不出现、多卡排序

## 2. 界面

- [ ] 2.1 资产页顶部「待还」提醒卡（账户名、应还金额、还有 N 天/今天到期/已逾期 N 天，≤3 天用警示色）；`test/pages/assets_page_test.dart` 或新用例：有提醒时显示、无提醒时不显示
- [ ] 2.2 账户编辑页：信用卡类型下出现「账单日/还款日」（1–28，可留空），其它类型隐藏；用例：信用卡显示、储蓄卡不显示、越界提示
- [ ] 2.3 `flutter analyze` 干净、`flutter test` 全绿（不低于 270 + 新增）

## 3. 回归

- [ ] 3.1 设备端回归：建一张信用卡账户、设还款日 → 记一笔支出 → 资产页出现「待还」与天数；结果写入 tasks.md

## Workflow follow-up

- 归档 change：`openspec archive credit-card-bills --yes`
- 归档后回写 `docs/PRODUCT_PLAN.md` §8（M6 状态）与 §14
