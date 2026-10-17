# Design

## 查询：先用 SQL 收敛，再用 Dart 做关键词

```dart
class LedgerFilter {
  final String keyword;          // 备注/分类/账户/标签 包含
  final EntryType? type;         // null = 全部
  final DateTimeRange? range;    // null = 全部时间
  final String? categoryId;      // 选中一级分类时包含其子分类
  final String? accountId;
  final String? tag;             // 标签名
  final int? minCents;
  final int? maxCents;
}
```

`searchLedger(filter, {limit = 2000})`：

1. SQL where：`type`、`happenedAt` 区间、`categoryId`（含子分类 id 集合）、`accountId`、`amountCents` 区间。
2. 取回行后装配成 `ExportRow` 同款结构（分类路径/账户名/标签/附件），关键词在内存里对「备注 + 分类名 + 账户名 + 标签」做 `toLowerCase().contains`。
3. 复用现有的按日分组逻辑 → 返回 `LedgerSnapshot`（groups + 命中总数）。

为什么关键词不在 SQL 里做：要跨 `transactions`/`categories`/`accounts`/`tags` 四张表做 `LIKE` + `JOIN`，代码量与索引成本远高于收益；本地账本量级（万级以内）在内存里匹配是毫秒级。

## 时间范围

```dart
enum SearchRange { thisMonth, lastThreeMonths, thisYear, all }
```

- `thisMonth`：`[月初, 次月初)`；
- `lastThreeMonths`：`[本月前两个月的月初, 次月初)`；
- `thisYear`：`[1 月 1 日, 次年 1 月 1 日)`；
- `all`：不限。

半开区间，避免 23:59:59 的毫秒漏账（与按月浏览一致）。

## 界面

### 搜索页（`SearchPage`）

```
← [ 搜索备注 / 分类 / 账户 / 标签        ]  取消
[全部][支出][收入]   [本月][近三月][今年][全部]   筛选
── 结果：按日分组，与明细同一套行 ──
```

- 输入即搜（`onChanged` + 200ms 去抖）；关键词为空也可以只靠筛选出结果。
- 「筛选」打开底部面板：分类（单选，含「不限」）、账户（单选）、标签（单选）、金额区间（两个输入框）。
- 已生效条件在输入框下方以胶囊展示，点胶囊上的 × 移除；「清空筛选」只清结构化条件，保留关键词（与 spec 一致）。

### 复用日分组列表

明细页里的 `_DaySection` / `_EntryRow` 抽到 `lib/widgets/ledger_day_list.dart`：

```dart
class LedgerDayList extends StatelessWidget {
  const LedgerDayList({required this.groups, this.attachments, required this.onOpen});
}
```

- 抽出的目的：搜索页与明细页必须长得一模一样（同一份排版规则只写一次）。
- 明细页保留自己的概览卡片与月份头，只把「日分组 + 行」交给这个 widget。

## 关键决策

| 决策 | 选择 | 理由 |
|---|---|---|
| 搜索与月份浏览的关系 | 独立搜索页，跨全部月份 | 「找一笔」不应被当前浏览的月份限制；月份浏览仍是首页的主线 |
| 关键词范围 | 备注 + 分类 + 账户 + 标签 | 用户记不住金额，但记得「在哪儿花的」 |
| 分类筛选是否含子分类 | 含 | 选「餐饮」应该连「餐饮/外卖」一起找出来 |
| 筛选存储 | 页面 State | 不做保存搜索（非目标），避免再引入一套持久化模型 |
| 结果上限 | 2000 条 | 防御性上限；命中更多时提示「结果过多，建议加条件」 |

## 风险

| 风险 | 应对 |
|---|---|
| 抽出日分组 widget 会碰坏明细页 | 明细页现有 widget test 全部保留，重构后必须一绿到底 |
| 去抖导致测试难写 | 测试里直接 `pump(300ms)` 推进；关键词过滤逻辑另有仓储单测兜底 |
| 大账本内存匹配慢 | 先用 SQL 收敛类型/时间/分类/账户/金额，关键词只在收敛后的集合上跑 |
