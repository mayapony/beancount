# Design

## Context

动机与真机证据见 `proposal.md`；行为契约见 `specs/auto-entry/spec.md`。

本文只记录**已经拍板**的技术决策。其余问题（排除词邻域、规则锚定、通知规则验证、抓帧时机）等真机测评结束后再补齐，避免方向反复。

现状约束：

- `transactions` 表当前 `schemaVersion = 5`，迁移用 `TableMigration(newColumns: …)` 加列（v2 加过 `toAccountId`，v3 加过循环记账两列）。
- 无障碍 / 通知路径已有 `CaptureCandidate.packageName`；截图路径的包名要到写账**之后**由 `dumpCurrentTree` 反查。
- 「最近自动记账」按 `source = auto` 过滤，交易详情页按行渲染字段。

## Goals / Non-Goals

**Goals:**

- 每笔自动入账能回答「这笔是从哪个 App 来的」，且不破坏现有去重键与统计。
- 迁移可回滚（`IF NOT EXISTS` 风格、失败不锁库），旧数据留空而不是伪造。

**Non-Goals:**

- 不记录来源页面的指纹或规则 id（那是运行记录的事，已有 `diag` 通道）。
- 不为手动记账补来源，也不在 UI 上对旧数据补「未知应用」。

## Decisions

### D1 在 `transactions` 上加一列，而不是新建附表

新增 `TextColumn get sourcePackage => text().nullable()()`，存 Android 包名（如 `com.taobao.taobao`）。

**理由**：

- 列表与详情都要展示，附表意味着每次查询多一次 join 或批量补查；
- 一笔交易只有一个来源，一对一，附表没有额外价值；
- 截图 / 无障碍 / 通知三条路径都在写账那一刻已知或已能取到包名，一列足够。

**备选（否决）**：

- `entry_origins(transactionId, package, target)` 附表 —— 为对一关系多付一次查询，且要多维护一张表的迁移与清理；
- 塞进 `note` —— `note` 参与去重键计算，改备注会改去重行为，污染面太大；
- 塞进 `tags` —— 标签是用户可见可编辑的概念，混入系统来源会让「标签筛选」失真。

### D2 迁移：schemaVersion 6，加列 + 不重建表

`onUpgrade` 新增 `if (from < 6)` 分支，用 `TableMigration(transactions, newColumns: [transactions.sourcePackage])`。旧行该列为 `NULL`，表示「来源未知」，界面不显示来源行。

**理由**：drift 的 `alterTable` 对纯加列会走 `ALTER TABLE ADD COLUMN`，不动数据、不动索引，是风险最低的迁移形态。

**验证**：`test/data/db_migration_test.dart` 增加「v5 → v6 旧账仍在、来源为空」的用例。

## 待定（等测评结束再补）

- **截图链路的写入顺序**：包名要提到写账之前取，还是写账后回填（当前流程是写账后才反查）。倾向前者，但要看 `screenshotEntry` 与 `ScreenshotService` 的现有调用顺序再定。
- **可读名从哪来**：直接存包名，还是再加一列可读名（应用名随系统语言/版本变，存快照有陈旧风险）；或只在 UI 侧用一张已知包名映射表。
- 问题 1–3、6 的判定语义与抓帧时机。

## Risks / Trade-offs

- [旧账没有来源，列表会出现「有的显示有的不显示」] → 统一按「来源未知就不显示来源行」处理，不补占位文案，避免每行都吊一个「未知」。
- [包名会变化（企业版/多渠道包）] → 存原始包名不做归一化，展示层再做映射；宁可显示原始包名，也不猜。
- [迁移失败] → 纯加列，无数据搬迁；失败时 drift 抛错会走既有错误处理，不会静默丢账。
