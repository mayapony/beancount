# Design

## 为什么是「打开即补」而不是后台定时

本地记账 App 没有理由为此背上 WorkManager：Android 的后台限制、开机的唤醒、厂商省电策略，每一条都会变成"为什么我的房租没记上"。
改成**每次打开 App 扫一次**：把上次补记之后到当前月之间应发生的期数补齐。用户感知上等价（打开就能看到），实现上只是一个确定性的批处理。

## 数据模型（schemaVersion 3）

```
recurring_rules
  id             TEXT PK
  type           TEXT     -- expense / income / transfer
  amount_cents   INTEGER  -- > 0
  category_id    TEXT NULL REFERENCES categories(id)
  account_id     TEXT NULL REFERENCES accounts(id)
  to_account_id  TEXT NULL REFERENCES accounts(id)
  note           TEXT
  day_of_month   INTEGER  -- 1..31，31 表示「月末」（29/30 同理落到当月最后一天）
  start_year     INTEGER  -- 生效起始月
  start_month    INTEGER
  enabled        INTEGER  -- 0/1
  created_at     INTEGER
```

**不存 `last_run_at`**：补记过程本身是可推导的——只要知道"已存在哪些期的交易"。判断依据是去重键的 **salt**：

```
dedupeKeyFor(..., salt: 'rule:<ruleId>:<yyyy-MM>')
```

这样同一规则同一期无论补多少次都只有一笔，且不需要额外字段去记"跑到哪了"（少一个会漂移的状态）。

### 迁移 v2 → v3

只新增一张表：`m.createTable(recurringRules)`，不动任何既有表。测试从 **v1 直接到 v3** 验证链式迁移（真实历史上用户的库就是 v1）。

## 日期规则

```
dayOfMonth = 31 → 当月最后一天
dayOfMonth = 29/30 → 当月没有这一天时落到月末
dayOfMonth = 1..28 → 就是那一天
```

补记范围：从 `max(规则起始月, 今天所在月)` 往回……不，是**从起始月到当前月**，但每期只在"该期执行日 <= 今天"时才补（当月还没到日子就不提前记）。

- 例：今天 10 月 8 日，规则每月 5 日、起始 7 月 → 补 7/5、8/5、9/5、10/5；11 月不补。
- 例：今天 10 月 3 日，规则每月 5 日、起始 7 月 → 补 7/5、8/5、9/5（10 月还没到）。

## 幂等

`RecurringService.applyDue(now)` 对每条启用规则：

1. 枚举 [起始月, 当前月] 内的每一期日期；
2. 跳过晚于 `now` 的期；
3. 对每期算 salt 去重键，调用 `TransactionRepository.create`（它本身"命中键不写入"）；
4. 汇总 `created / skipped` 返回给启动流程（不弹窗，只在 debugPrint 里留一行）。

`create` 已有的「同键不写入」保证并发/重复启动都安全。

## 界面

### 规则列表（`RecurringPage`）

```
房租            每月 5 日 · ¥2,500.00    下次 11月5日   ›
工资            每月 10 日 · +¥14,519.01  下次 11月10日  ›
[已暂停] 宽带   每月 20 日 · ¥99.00       继续执行        ›
```

点行 → 编辑面板（与新建同一套）：类型分段、金额、分类或两端账户、「每月几号」胶囊（1–28 + 月末）、备注、启用开关、删除。

### 备注历史

备注弹窗顶部加一行「最近用过」：最多 8 个胶囊，点一下填入输入框。数据来自 `recentNotes(limit: 8)`：
`SELECT note FROM transactions WHERE note <> '' GROUP BY note ORDER BY MAX(happened_at) DESC LIMIT ?`。

## 关键决策

| 决策 | 选择 | 理由 |
|---|---|---|
| 触发方式 | 打开 App 补记 | 无后台调度复杂度，行为可预测、可测试 |
| 期数判定 | 去重键 + salt | 不维护 lastRun 状态，天然幂等 |
| 频率 | 每月（含月末） | 房租/工资/宽带/会员都是月付；周/年等以后再加 |
| 规则暂停 | `enabled` 布尔 | 删除是破坏性操作，暂停更常用 |
| 历史备注 | 从真实交易取 | 零维护，天然跟随用户习惯 |

## 风险

| 风险 | 应对 |
|---|---|
| 补记把用户不想要的月份也补了 | 起始月由用户指定；改规则不影响历史（键已固定） |
| 首次启用补出一堆历史 | 这正是"房租补记"的预期；测试覆盖「起始 7 月、10 月首启 = 4 笔」 |
| 启动时补记拖慢冷启动 | 规则通常个位数、期数有限；`applyDue` 异步执行，不阻塞首帧 |
| 迁移链 v1→v3 | 迁移测试从 v1 DDL 开始，验证两步迁移后的表结构与数据 |
