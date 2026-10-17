# Design

## 数据层

### 查询：按月范围

`dayGroups` / `watchDayGroups` 增加可选 `year` + `month`：

```
WHERE happenedAt >= 月初 AND happenedAt < 次月初
```

- 用半开区间（`< 次月初`）而不是 `<= 月末 23:59:59`，避免毫秒精度漏账。
- 月份给定时**不施加 500 条上限**（spec 要求整月完整）；未给定时保留上限，供「全部」类旧调用过渡。
- 月份参数在仓储层转成 `DateTime` 区间，页面只传 `year`/`month` 两个 int，避免时区与创建方式分歧。

### 编辑

新增 `TransactionRepository.update(TransactionEdit)`：

1. 金额、时间、备注变化时按新值重算 `dedupeKey`；只改分类/账户/标签时复用原键（减一次无谓冲突判断）。
2. 冲突检查排除自身：`WHERE dedupeKey = ? AND id != ?`，命中则抛 `DuplicateTransactionException`，UI 提示后保持面板打开。
3. 在同一个 `transaction()` 里：`update` 交易行 → 删掉该交易的 `transaction_tags` → 按新标签重新插入（`_ensureTag` 复用同名标签）。
4. **不动附件**：编辑只改字段，图片的增删是另一件事（本次非目标）。

### 删除

`TransactionRepository.delete(id)`：

1. 先读出该交易的附件文件名（删除后 `attachments` 行会随外键级联消失，读不到了）。
2. 在事务里 `delete` 交易行；`transaction_tags` 与 `attachments` 均 `ON DELETE CASCADE`，无需手工清理。
3. 对每个文件名做引用计数：仍被其他交易引用则保留，计数为 0 才 unlink 磁盘文件。等价于 `AttachmentRepository` 里已有的引用回收逻辑，本次把它接到「删除交易」这条路径上。

### 详情页取数

进入详情时用 `TransactionRow`（列表已有）直接渲染，避免再查一次；编辑/删除后页面 `pop`，明细依靠 `tableUpdates()` 流自动刷新——不新增回调链路。

## 界面

### 月份状态

`TransactionsPage` 持有一个 `_Month({year, month})`：

- `initState` 落当月；切月时 `setState` 重建 `Stream`（`watchDayGroups(year:, month:)`）。
- 标题：`BeanLargeTitle(title: '${month}月', subtitle: '${year}年 · N 笔收支')` —— 月份就是标题（沿用既定设计）。
- 左右滑动：列表外套 `GestureDetector.onHorizontalDragEnd`，速度阈值 200px/s，向上/下滚动不受影响。
- **不持久化浏览月份**：每次进 App 回到当月，符合「月底看这个月」的主线。

### 月份选择器

新增 `MonthPickerSheet`（底部面板，沿用现有面板语言：暖灰拖拽条、40 圆关闭键、砂底胶囊、金色选中）：

- 顶部一行 `‹ 2026 ›` 年份步进 + 右侧「回到本月」文字按钮。
- 下面 3×4 网格列出 1–12 月，当前浏览月金色实心，当月用描边额外标记。
- 点月份即选中并关闭；无数据月份也可选（会落到空月状态）。

### 空状态分两种

| 条件 | 文案 |
|---|---|
| 整库无交易 | 「还没有记账」+ 点金豆记第一笔 |
| 当前月无交易 | 「这个月还没有记账」+ 「回到本月」/「换个时间段」 |

### 交易详情页

结构（单页，`Scaffold` + 发丝线卡片）：

```
金额大字（-¥45.00） + 分类头像
分类 / 账户 / 时间 / 备注 / 标签   ← 逐行 label-value
图片（横向 96×96 缩略图，点开大图）
[编辑]  [删除]
```

- 删除入口放在底部，用警示色**文字按钮**（不是实心红按钮），避免误触；确认用 `showDialog` + `AlertDialog`，正文含金额。
- 编辑复用 `QuickEntrySheet`：新增可选 `initialDraft`，预填金额/类型/分类/账户/时间/备注/标签；新增模式不传该参数，行为完全不变。

## 关键决策

| 决策 | 选择 | 理由 |
|---|---|---|
| 月份状态存哪 | 页面 State | 不需要跨会话记忆，避免 app_state 增负担 |
| 删除是否可撤销 | 不做 | 撤销需要软删除 / 回收站，会把「物理删除 + 外键级联」的简单模型推翻（§6 已明确放弃软删除） |
| 编辑是否允许改图 | 不做 | 图片增删涉及文件选择器与 M7 视觉识别，另开 change |
| 去重键冲突的表现 | 抛异常 + 面板提示 | 与导入「不覆盖、只插入」的策略一致，避免静默改掉另一笔 |
| 编辑面板 | 复用 `QuickEntrySheet` | 两套录入界面必然漂移；预填成本低于新建 |
| 月份查询上限 | 月内不设限 | spec 明确「整月完整」；真正需要防的是全库无界查询，已被月份约束替代 |

## 风险

| 风险 | 应对 |
|---|---|
| `QuickEntrySheet` 1566 行，加预填易碰坏新增路径 | 预填走独立参数；`test/widgets/quick_entry_sheet_test.dart` 补「传入草稿时预填」「不传时继承上次选择」两条 |
| 左右滑动与底部 FAB 手势冲突 | FAB 在页面外层的 `Stack`，只吃掉自身命中区；滑动用 `onHorizontalDragEnd` 且带速度阈值 |
| 详情页删除后返回，列表闪一下旧数据 | 删除在 `await` 完成后才 `pop`，流更新先于返回；若仍有闪动，返回前用本地占位移除该行 |
| 月份切换重建 Stream 造成重复查询 | 每次切月只建一条流；`StreamBuilder` 复用同一 key，避免每帧重建 |
