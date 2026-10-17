# Tasks

## 1. 推导与仓储

- [x] 1.1 新增 `NetWorthRange` / `NetWorthPoint` / `NetWorthSeries` 与 `NetWorthRepository.load({range, now})`：初始余额作为基线、按月累加收入与支出、跳过转账；`test/data/net_worth_repository_test.dart` 覆盖「收入上升」「支出下降」「转账不变」「初始余额不进任何月」
- [x] 1.2 三档范围的月份序列：近 6 个月 6 个点、今年从 1 月起、全部从最早一笔所在月起；用例各一条
- [x] 1.3 `watch({range})` 随表变化重发；用例：记一笔后订阅收到新值
- [x] 1.4 `changeCents` 与 `isEmpty` 语义；用例：空账本 isEmpty、两点之间的差值正确

## 2. 资产页

- [ ] 2.1 资产页接收 `NetWorthRepository`，新增「净资产走势」卡片：当前值 + 变化额 + 三档胶囊；`test/pages/insights_assets_page_test.dart` 用例断言渲染与切换后点数变化
- [ ] 2.2 走势图用 fl_chart 绘制（允许负值、不显示纵轴刻度和网格竖线）；用例：有点时出现 `LineChart`，空账本显示「还没有足够的数据」
- [ ] 2.3 Shell 把 `NetWorthRepository` 传给资产页；用例：入口页可构建

## 3. 回归

- [ ] 3.1 `flutter analyze` 干净、`flutter test` 全绿（不低于 202 + 新增）
- [ ] 3.2 设备端回归：记两笔账 → 资产页曲线出现 → 切三档点数正确 → 改一笔金额后曲线变化；结果写入 tasks.md

## Workflow follow-up

- 归档 change：`openspec archive net-worth-trend --yes`
- 归档后回写 `docs/PRODUCT_PLAN.md` §8（M6/M5 状态）与 §14
