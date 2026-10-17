# Design

## 数据：两个可空的小整数

```dart
IntColumn get billingDay => integer().nullable()();
IntColumn get dueDay     => integer().nullable()();
```

- 取值 1–28：29–31 在大月/2 月会漂，提醒的本质是"大致这几天"，没必要为 31 号写月末回退规则（那是循环记账的需求，不是还款提醒的）。
- `schemaVersion = 4`，迁移只 `alterTable(TableMigration(accounts, newColumns: [billingDay, dueDay]))`，既有行两列都是 null，不影响余额与统计。

## 推算

```dart
class CardDue {
  final Account account;
  final DateTime dueDate;     // 下一个还款日（>= 今天）
  final int owedCents;        // 余额的绝对值
  int daysLeft(DateTime now); // 今天到期 = 0；逾期为负（理论上不会，因为取的是 >= 今天）
}

List<CardDue> dueReminders({DateTime? now})
```

规则：

1. 只取 `type == credit`、`dueDay != null`、`balanceCents < 0` 的账户；
2. 本月还款日 = `DateTime(now.year, now.month, dueDay)`；
3. 若本月还款日 `< 今天` → 用下月（`DateTime(now.year, now.month + 1, dueDay)`，DateTime 会自动跨年）；
4. 排序：`daysLeft` 升序，再按应还金额降序。

「逾期」在模型里其实不会出现（我们取的是"下一个"），但日期变化（比如改系统时间）可能让 `dueDate < today`，
所以 `daysLeft` 允许为负，界面按「已逾期 N 天」显示，不隐藏。

## 界面

资产页顶部：

```
┌────────────────────────────────────┐
│ 待还                            3 天后 │
│ 招商银行信用卡     应还 ¥3,200.00     │
└────────────────────────────────────┘
```

- 只有存在提醒时才出现；单张卡时把账户名与金额放同一行，多张时列表。
- 剩余天数用颜色表达紧急度：≤3 天用 `palette.alert`，其余用次要文字色。
- 点卡片进入账户页（后续可加"去还款"按钮，本轮不做）。

账户编辑页：

- 「信用卡」类型下出现「账单日」「还款日」两个数字输入（1–28，可留空）；
- 其它类型隐藏，避免把储蓄卡也填上日子造成误解。

## 关键决策

| 决策 | 选择 | 理由 |
|---|---|---|
| 日号范围 | 1–28 | 避开大小月与 2 月的漂移；提醒不需要精确到 31 |
| 是否存「下个还款日」 | 不存，按需算 | 存下来会随系统时间过期，算的成本极低 |
| 应还金额 | 余额绝对值 | 与账户余额同一个真相，不做"已还部分"的推断 |
| 是否自动生成还款交易 | 不做 | 自动记账会污染真实流水，用户自己记更可靠 |
| 是否只对 credit 生效 | 是 | 储蓄卡没有"还款"语义 |

## 风险

| 风险 | 应对 |
|---|---|
| 用户填 31 号 | 输入限定 1–28，越界拒绝并提示 |
| 余额为正（多还了） | 不提醒，避免"倒欠"歧义 |
| 改系统时间导致逾期显示 | 允许负 daysLeft 并显示「已逾期 N 天」 |
| 多卡同名 | 行里同时显示应还金额，避免混淆 |
