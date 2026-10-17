# Design

## 数据：一个查询，复用已有的分组

```dart
class CategoryLedger {
  final List<DayGroup> groups;   // 与明细页同一个分组结构
  final int totalCents;
  final int count;
}

Future<CategoryLedger> categoryLedger(
  String rootId, {DateTime? from, DateTime? to, int limit = 1000}
)
```

实现：

1. `childrenOfCategory(rootId)` 拿子分类 id，条件 `category_id IN (root, ...children)`；
2. `happenedAt` 落在 `[from, to)`（null 表示不限）；
3. 复用 `_rowsFor()` + `_groupByDay()`，所以转账自动被排除在合计之外、金额符号与明细页一致。

为什么不复用 `searchLedger`：它的时间范围是三个固定枚举，而下钻要跟洞察页的「今年/全部」精确对齐，传 `from/to` 更直接，也少一层过滤。

## 页面

```
‹ 餐饮                      [合计 ¥1,240.80]
2026年10月 · 12 笔 · 占本月支出 31%
────────────────────────────────
10月17日 周五                 -¥38.50
  街角炸鸡   餐饮/外卖
────────────────────────────────
10月12日 周一                -¥120.00
  ...
```

- 头部用 `BeanLargeTitle` 的变体：大号合计 + 一行灰字（范围/笔数/占比）。占比由调用方算好传进来（洞察页已有 `total`）。
- 列表直接用 `LedgerDayList`，与明细页同一套行样式；点击 → `TransactionDetailPage`。
- 空状态：`BeanEmptyState('这段时间没有这一类支出')`。

## 入口

`_LegendItem`（图例胶囊）与排行行都包一层 `InkWell`，点击调用 `onDrillDown(category)`；
`InsightsPage` 负责 push，避免展示组件知道路由。

## 关键决策

| 决策 | 选择 | 理由 |
|---|---|---|
| 复用 `DayGroup` | 是 | 行样式、合计口径、日期分组都已验证过 |
| 用 `from/to` 而不是 `LedgerFilter` | 是 | 洞察页有「今年/全部」两种非枚举范围 |
| 占比从上层传入 | 是 | 洞察页已经算过总计，下钻页不必再查一遍 |
| 是否允许再筛选 | 不做 | 下钻是"看一眼就走"，再筛选请回搜索页 |

## 风险

| 风险 | 应对 |
|---|---|
| 分类被删后点进去 | 传入的是当前快照里的分类；分类删除时会迁移账目，不会留下悬空 id |
| 大量账目 | `limit 1000` + 按日分组；超出时页脚说明"只显示最近 1000 笔" |
| 二级分类 id 与父 id 混用 | 条件里两者都在 `IN` 里，父分类自身的账也不会漏 |
