# Proposal

## Why

记账面板的默认值与分类供给都还停在"够用就好"的阶段：收支类型继承了上一笔（上一笔记的是收入，下次打开就还是收入，而支出才是高频场景）；账本只种了 12 个一级分类，内置分类库里 40 多个二级分类要靠用户逐个手动新建；自动入账的来源应用只存在一个字段里，不能像标签那样被搜索和筛选；「待处理 · 选账户」的标记在用户从详情页改完账户后仍不清除，导致列表里长期挂着已经处理过的行。

## What Changes

- **收支类型不再继承**：记一笔面板默认永远停在「支出」，只继承分类与账户。上次记的是收入也还是从支出开始。
- **分类库一次给全**：账本种子改为内置分类库的一级 + 二级分类（44 个二级 + 2 个新增一级），老账本按映射表增量补齐，用户不用再手动添加常见分类。
- **自动新建分类的配额口径改变**：总数上限从「账本分类总数 ≤ 40」改为「自动创建过的分类 ≤ 40」——否则种完分类库后自动新建会永久失效。**BREAKING**：升级后旧账本的分类数会一次性增加约 46 个。
- **来源应用变成标签**：自动入账时按来源应用自动打一个标签（京东 / 支付宝 / 微信 …），搜索页的标签筛选与详情页的标签区立刻可用。
- **编辑即清「待处理」**：从详情页保存一笔自动账后，只要用户动过账户或分类，就清除待人工处理的标记。
- **分类使用笔数忽略无分类的交易**：转账没有分类，原来会被算成一组「NULL 分类」，分类管理页因此整页空白；改成只统计挂了分类的交易。

## Capabilities

### New Capabilities

（无）

### Modified Capabilities

- `ledger-storage`: 「上次记账选择」只记忆分类与账户，收支类型 MUST NOT 继承，默认支出。
- `ledger-taxonomy`: 首次启动种子改为分类库全集；自动新建分类的总数配额改为统计自动创建数量；自动入账 SHALL 按来源应用自动关联标签；分类使用笔数 MUST 忽略没有分类的交易（转账）。
- `ledger-editing`: 编辑已自动入账的交易后 SHALL 清除待人工处理标记。

## Impact

- 种子与迁移：`lib/data/seed.dart`、`lib/data/category_library.dart`（新增「库 → 账本」映射）、`lib/data/db/app_database.dart`（schemaVersion 6 → 7，升级时增量补分类）
- 记账面板：`lib/widgets/quick_entry_sheet.dart`（默认类型）、`lib/pages/shell.dart`（`initialIsIncome`）
- 自动入账：`lib/services/screenshot/auto_entry.dart`、`lib/services/capture/capture_entry_saver.dart`（写来源标签）
- 配额：`lib/services/ocr/auto_create_policy.dart`（总数口径）
- 编辑：`lib/data/repositories/transaction_repository.dart`（`TransactionEdit` / `update()`）、`lib/pages/transaction_detail_page.dart`
- 风险：老账本的分类树会一次性变宽，洞察页的分类占比会多出许多细项；迁移必须幂等且只增不改已有分类的 id 与名称
