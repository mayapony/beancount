# Design

## Context

当前 `lib/data/` 只有一个 `demo_data.dart`（常量 + `DemoAccount` 等只读模型）；`quick_entry_sheet.dart` 产出 `QuickEntryDraft` 后由 `shell.dart` 弹 SnackBar 丢弃；三个页面直接引用 demo 常量，分类通过 `BeanColors.categoryNames` 的**数组下标**贯穿（`CategoryAvatar(categoryIndex:)`、`kQuickCategoryOrder`、图表色 `categories[index]`）。

约束：
- 目标平台 Android / iOS，Web 只用于预览（不能因存储不可用而白屏）。
- 项目语言 zh，规范文件 `docs/DESIGN.md` 与 `docs/review/` 已定视觉；本设计只做数据层，不重做 UI。
- 还没有任何已落地的表结构，可以从零设计。
- 后续紧接着要做 BeeCount CSV 导入，数据模型必须能容纳"外部命名的一二级分类、任意账户名、任意标签"。

## Goals / Non-Goals

**Goals:**
- 一条可用的写入 → 读取链路：记一笔落库，明细/洞察/资产读库。
- 分类从"下标"迁移到"带 id 的记录"，并保证历史引用不漂移。
- 金额整数分、去重键唯一、升级不清库。
- 记账凭证图片随交易保存（真实导出里 47/48 笔带截图，见下）。
- Web 上不崩溃（降级为内存库，可预览）。

**Non-Goals:**
- 不做云同步 / 多币种换算 / 转账记录。
- 不做数据导入（下一个变更）；但表结构必须能容纳导入的附件。
- 不做账户余额的历史快照（只按交易推导当前余额）。
- 不做图片压缩、OCR、缩略图缓存（原图直接落盘，展示时用 `Image.file` + `cacheWidth`）。

## Decisions

### 1. 存储引擎：drift（SQLite）

- **选择**：`drift` + `sqlite3_flutter_libs`，Web 端用 `drift/wasm` 或降级内存实现。
- **理由**：导入与统计都要聚合（按月/按分类 GROUP BY），SQL 比键值库省事；drift 有类型安全、可写迁移（`schemaVersion` + `MigrationStrategy`），符合"数据可迁移"的产品原则。
- **备选**：`sembast`（零代码生成、纯 Dart，但聚合要手写）；`isar`（已停止维护）；`sqflite`（无 Web、无类型）。
- **代价**：引入 `build_runner` 代码生成；Web 需要 wasm + worker 配置，本变更允许 Web 走内存实现避免阻塞移动端。

### 2. 表结构（5 张主表 + 2 张从属表）

```
categories(id, name, type, parent_id, color, icon, sort_order, created_at)
accounts(id, name, type, initial_balance_cents, sort_order)
tags(id, name UNIQUE)
transactions(id, type, amount_cents, category_id, account_id, note,
             happened_at, dedupe_key UNIQUE, created_at)
transaction_tags(transaction_id, tag_id)      -- 多对多
attachments(id, transaction_id, file_name, original_name, file_size,
            sort_order, created_at)           -- 一笔可多张，可跨交易共享同一文件
app_state(key PRIMARY KEY, value)             -- 上次选择，不另建表
```

- `categories.type` ∈ {expense, income}；`parent_id` 自引用，最多两级（应用层校验，DB 只保证外键）。
- `transactions.category_id` 指向**最细一级**（二级分类时存二级的 id），统计时通过 `parent_id` 上卷。
- `dedupe_key` = `hash(happenedAt 到秒, amount_cents, trim(note))`，`UNIQUE` 索引；用文本列存 32 位 hex，避免复合唯一索引在不同 SQLite 版本的兼容问题。
- `attachments.file_name` 是应用私有目录 `attachments/` 下的文件名（不存绝对路径，避免沙盒路径变化导致失效）；`file_name` 不唯一——真实导出里有两笔交易共用同一张截图（`sha_9a55…jpg`），所以文件存一份、记录存两条，删除记录时要按引用计数决定是否删文件。


### 3. 金额：整数分

`amount_cents INTEGER`，输入 `38.5` → `3850`；读取统一走 `formatMoney(cents / 100)`。运算（+ −）在分上做，避免浮点。

### 4. 分类 id 化：一次性替换下标

- `CategoryAvatar` 改为接收 `Category`（或 `color` + `icon`），不再接收 `categoryIndex`。
- 记一笔网格渲染 `List<Category>`，顺序由 `sort_order` 决定；`kQuickCategoryOrder` 删除，改为查询"最近使用 + 排序"。
- 图表颜色改为读分类记录的 `color`，`BeanColors.categories` 只作为种子颜色池。
- 由于 demo 数据仍在（预览 / 空库），保留一个 `demo_data.dart` 的种子映射函数，把 index → 默认分类记录。

### 5. 首次启动种子

`onCreate` 里写：

- **12 个支出分类**（餐饮 / 交通 / 购物 / 娱乐 / 居家 / 医疗 / 教育 / 旅行 / 运动 / 数码 / 宠物 / 其他），颜色/图标取现有 `BeanColors` 与 `kCategoryIcons` 的同序；
- **6 个收入分类**（工资 / 奖金 / 兼职 / 理财 / 红包 / 其他收入）。当前记录面板切到「收入」时复用的是同一批支出分类，会出现"收入 · 餐饮"这种语义错误，种子必须按 `type` 分开，面板网格也改为按当前类型过滤；
- 1 个「默认账户」（`initial_balance_cents = 0`）、无标签。

种子写入用固定 id（如 `cat-food`…）保证幂等，重复执行不产生重复行。

### 6. 上次选择

`app_state(key TEXT PRIMARY KEY, value TEXT)` 存 `last_category_id` / `last_account_id` / `last_type`；`shell.dart` 打开面板前读取，提交成功后写回。不另建表。

### 7. Web 降级

`DatabaseConnection` 在 `kIsWeb` 时用 `NativeDatabase.memory()`（drift 的内存实现）；移动端用文件库。这样 Web 预览不会因为缺 wasm 资源白屏，但刷新即丢——README 注明仅预览用。

### 8. 附件：表 + 私有目录落盘

- **存放**：`<applicationDocumentsDirectory>/attachments/<fileName>`；数据库只存文件名与元信息。图片是**原始字节**，不转码不压缩。
- **写入时机**：先写文件、再写记录；文件写失败则整笔交易失败（不产生"有记录没图"）。
- **删除**：删除交易时删除其附件记录；随后用 `SELECT COUNT(*) FROM attachments WHERE file_name = ?` 判断，计数为 0 才删除磁盘文件（真实数据里存在跨交易共享）。
- **展示**：明细行右侧 32×32 圆角缩略图（`cacheWidth` 限流），点击进入可横滑的大图页；无附件不占位。
- **给导入的接口**：仓储暴露 `addAttachment(transactionId, File)` / `attachmentsOf(transactionId)`，供下一个变更的 BeeCount 导入直接调用。
- **代价**：真实导出约 20 MB / 46 张，首次导入会明显耗时，报告里要显示"图片 N 张 / X MB"。

## Risks / Trade-offs

- [drift 代码生成增加了构建步骤] → 生成文件入库（`*.g.dart` 提交），CI/新机器无需先跑 `build_runner` 即可编译。
- [分类下标替换会牵动 4 个页面 + 2 个组件，回归面大] → 先加"兼容层"（`Category` 携带 legacyIndex），页面逐步迁移，最后一个任务删兼容层。
- [去重键把"同一秒、同金额、同备注"的两笔真实交易判为重复] → 概率极低；真出现时允许用户在导入报告中"强制导入"，记账路径不受影响。
- [Web 内存库让预览与移动端行为不一致] → 仅在 Web 生效并写进 README/design 备注，不参与验收。
- [首次种子与用户已有 demo 数据的关系] → 只播种分类/账户/标签，不播种交易；空账本仍显示空状态（符合 `ledger-storage` 的空状态场景）。
- [账户初始余额统一按 0 起算（已确认的决策）] → demo 里 1,240.55 / 28,560.00 / −3,280.40 不再作为真实余额展示；导入前资产页只有「默认账户 ¥0.00」，导入后按 48 笔交易推导出 支付宝 −1,728.50 / 微信 −1,085.19 / 招商银行 +14,243.40。风险是"看起来钱变少了"，需在导入报告里写明"余额由交易推导"。
- [附件占磁盘且用户无法清理] → 删除交易时按引用计数删文件；后续可加"清理未引用图片"（本变更不做）。
- [附件失败会拖垮记账] → 只在用户主动添加图片时才走文件写入；不添加图片的记账路径完全不依赖文件系统。

## Migration Plan

1. 加依赖与 `AppDatabase`，第一次启动建表 + 种子；此时 UI 仍读 demo 数据（不破坏现状）。
2. 切换记一笔写入库；明细页读库（空库显示空状态）。
3. 切换洞察 / 资产读库与分类记录；接上附件写入与缩略图展示。
4. 回归：Android 真机/模拟器、Web 预览各跑一遍；`flutter test` 增加仓储层单测。
5. 回滚策略：数据库文件独立于 App 资源，回滚版本不清库；如需回滚到 demo 数据版本，旧版本会忽略新库文件，不产生数据损坏。
