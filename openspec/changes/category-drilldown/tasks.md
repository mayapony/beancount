# Tasks

## 1. 仓储

- [ ] 1.1 `TransactionRepository.categoryLedger(rootId, {from, to, limit})`：含子分类、按日分组、合计只算支出、返回笔数；`test/data/category_ledger_test.dart` 用例：含子分类、排除其它分类、from/to 边界、空结果
- [ ] 1.2 超出 limit 时只取最近 N 笔；用例：1200 笔时返回 1000 笔且笔数与合计基于返回集

## 2. 下钻页

- [ ] 2.1 新增 `CategoryLedgerPage`：标题为分类名与合计、副标题为范围/笔数/占比、列表按日分组、行可点开详情；`test/pages/category_ledger_page_test.dart` 用例：渲染合计与行、点行打开详情
- [ ] 2.2 空状态：该期间无账目时显示「这段时间没有这一类支出」；用例一条
- [ ] 2.3 范围随洞察页：月/年/全部三种 from-to 传递；用例：月范围只显示本月账

## 3. 入口

- [ ] 3.1 洞察页图例胶囊与排行行可点，push 下钻页（传入分类、期间、总计用于占比）；用例：点「餐饮」进入页面
- [ ] 3.2 `flutter analyze` 干净、`flutter test` 全绿（不低于 253 + 新增）

## 4. 回归

- [ ] 4.1 设备端回归：洞察页点分类 → 下钻页出现分类账目 → 点一笔进详情 → 返回；结果写入 tasks.md

## Workflow follow-up

- 归档 change：`openspec archive category-drilldown --yes`
- 归档后回写 `docs/PRODUCT_PLAN.md` §8（M5 状态）与 §14
