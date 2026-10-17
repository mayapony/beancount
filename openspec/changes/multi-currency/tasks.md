# Tasks

## 1. 数据层

- [ ] 1.1 accounts 加 `currency`（默认 `CNY`）、transactions 加 `currency`（默认 `CNY`）/ `originalAmountCents` / `ratePpm`，`schemaVersion = 5` + 迁移；`test/data/db_migration_test.dart` 用例：v1→v5、全新库两列都在
- [ ] 1.2 新增 `lib/utils/fx.dart`：`baseCentsOf(originalCents, ratePpm)`（四舍五入到分）、`ppmOf(double)`、`rateTextOf(ppm)`；`test/utils/fx_test.dart` 用例：7.25 整数换算、四舍五入边界、非法汇率
- [ ] 1.3 `NewTransaction` 接受 `currency` / `originalAmountCents` / `ratePpm`，落库时算本位币；非 CNY 缺汇率抛 ArgumentError；`test/data/multi_currency_test.dart`：USD 100@7.25 → 72500、同月合计 825 元、缺汇率被拒

## 2. 交互

- [ ] 2.1 记一笔：选中非 CNY 账户时显示汇率行（默认读 `app_state.fx_<CODE>`），保存后记住该币种汇率；`test/widgets/quick_entry_sheet_test.dart` 用例：USD 账户出现汇率行、填写后草稿带原币与汇率
- [ ] 2.2 账户管理：新建/编辑可选币种（先给 CNY/USD/EUR/JPY/HKD 五个 + 自定义），账户行显示非 CNY 标签；用例：选 USD 保存后可读回
- [ ] 2.3 明细行与详情页：非 CNY 显示原币 + 折合本位币（详情另给汇率一行）；用例：USD 交易的显示文案
- [ ] 2.4 `flutter analyze` 干净、`flutter test` 全绿（不低于 283 + 新增）

## 3. 回归

- [ ] 3.1 设备端回归：建 USD 账户（汇率 7.25）→ 记一笔 USD 100 → 明细显示原币与折合 → 洞察合计按 725 元计；结果写入 tasks.md

## Workflow follow-up

- 归档 change：`openspec archive multi-currency --yes`
- 归档后回写 `docs/PRODUCT_PLAN.md` §8（M6 状态）与 §14
