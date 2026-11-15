# Design

## Context

账本种子（`lib/data/seed.dart`）是 12 个扁平支出分类 + 6 个收入分类，id 固定为 `cat-food` / `cat-transport` …；内置分类库（`lib/data/category_library.dart`）是另一套结构：12 个一级 + 40 多个二级，带别名与图标，但**只用于搜索与提示词**，不落库。两套一级名并不一一对应，且库里有两个分类在账本里本来就是一级（数码、运动）。

`AutoCreatePolicy` 的总量闸门是 `categoryTotal >= 40`，入参是账本里分类的实际条数——种子一放宽就会永久失效。

去重键与「上次记账选择」的位置：

```
app_state
  last_category_id / last_account_id / last_is_income   ← quick entry 的默认值来源
  auto_create_category_log                              ← 7 天窗口的创建时间戳
transactions.needs_review                               ← 待人工处理标记（可空）
```

`transaction_repository.update()` 的入参 `TransactionEdit` 没有 `needsReview` 字段，写库用的 `TransactionsCompanion` 也不含该列，所以详情页保存永远不改这个标记。

## Goals / Non-Goals

**Goals:**

- 记账面板一次就能点到常用的一级与二级分类，不需要手动添加
- 分类库成为唯一供给来源，不再维护第二套名字
- 老账本升级不丢、不改名、不重复
- 来源应用可被标签筛选；「待处理」不再永久挂着

**Non-Goals:**

- 不改分类的两级上限，不引入第三级
- 不改洞察页的汇总口径（二级仍归一级统计）
- 不迁移用户的旧分类名（例如把「餐饮」改名成「食品餐饮」）

## Decisions

### 1. 显式映射表，库的一级融进账本已有的一级

新增 `libraryRootToLedger`（`lib/data/category_library.dart`）：

| 分类库一级 | 账本一级 | 说明 |
|---|---|---|
| 食品餐饮 / 出行交通 / 购物消费 / 居家生活 / 休闲娱乐 / 健康医疗 / 文化教育 / 旅行 / 宠物 / 其他 | 餐饮 / 交通 / 购物 / 居家 / 娱乐 / 医疗 / 教育 / 旅行 / 宠物 / 其他 | 复用已有 id，只挂二级 |
| 送礼人情 | 新建「人情」 | 账本没有这类 |
| 通讯网络 | 新建「通讯」 | 账本没有这类 |
| （购物消费/数码电器） | 不建 | 账本已有「数码」一级 |
| （健康医疗/健身运动） | 不建 | 账本已有「运动」一级 |

- 为什么不直接用库的一级名替换账本名：改名会让用户认不出自己的账本，也可能与用户自建的分类撞名；短名在 5 列网格里也更好排。
- 为什么「数码」「运动」保留为一级而不是挪成二级：已有交易引用的是它们，层级调整要连带迁移交易，代价远大于收益。

### 2. 升级走「增量补齐」，schemaVersion 6 → 7

`onUpgrade(from < 7)` 里执行一次 `seedCategoryLibrary(this)`（同一个函数也由 `onCreate` 调用）：

1. 按映射表取到（或创建）一级分类；
2. 对每个二级分类，用 `CategoryRepository.ensure(name, type, parentId)` —— 已存在则复用，不存在才插入；
3. 顺带做一次数据修复：`UPDATE transactions SET needs_review = NULL WHERE account_id IS NOT NULL AND needs_review = 1`。

幂等性由「同一父级下同名即复用」保证，重复执行不产生重复行；已有分类的 id、颜色、图标、排序一动不动。

### 3. 配额改数「自动创建出来的分类」

`AutoCreatePolicy` 不再接收账本分类总数，改为读 `app_state.auto_create_category_ids`（自动创建的分类 id 列表）：

- `checkCategory({enabled})` 用 `ids.length >= 40` 判总量，7 天窗口仍走原有时间戳日志；
- `markCategoryCreated(String id)` 同时写时间戳与 id 列表（两处去重）；
- 三个调用点（详情面板、截图入账、捕获入账）都能拿到刚创建的分类对象，传 id 即可。

这样种子带来的 60 多个分类不计入配额，用户升级后自动新建仍然可用。

### 4. 来源标签写在入账处，不受开关约束

`sourceAppName(packageName)` 已有映射（京东 / 支付宝 / 微信 …），直接作为标签名：

- `CaptureEntrySaver.save()` 与 `AutoScreenshotSaver.save()` 在调用 `EntryWriter.submit` 时把来源标签**追加**到 tags 末尾（`autoTags` 关掉时也追加）；
- 名称归一化后与既有标签同名则复用（走 `EntryWriter` 既有的 `_ensureTag`）；
- 来源包名未知（截图时窗口是系统界面）时什么都不加。

为什么放在入账处而不是展示处：标签是账本事实，放在展示层会在导出、搜索、备份里缺失。

### 5. 「待处理」由账户是否存在决定

`update()` 里：

```dart
needsReview: input.accountId != null
    ? const Value(null)      // 用户补了账户 → 标记结束
    : const Value.absent(),  // 账户仍空 → 不动标记
```

标记的语义收窄为「账户未知」，「最近自动记账」里的选账户路径本来就是这个语义（`assignAccountAndClearReview` 不变）。加上 §2 的升级修复，用户账本里那 3 条「有账户还挂着待处理」的记录会在升级时自动消失。

## Risks / Trade-offs

- **分类树一次性变宽**：升级后支出分类从 12 个涨到 58 个，洞察页的分类占比会碎成很多细项。缓解：洞察默认按一级汇总（现有 `category-drilldown` 行为），二级只在展开时出现。
- **种子与用户自建撞名**：如果用户已经自建过「打车」，`ensure` 会复用它而不是新建；若用户已有同名但挂在另一个父级下，则会出现两个「打车」——这是允许的（同级唯一，不同父级可同名），但需要在分类管理页能看出区别。
- **来源标签污染标签体系**：标签会随自动入账增长（每个来源应用一个）。上限就是用户装过的支付类 App 数量，可接受；若用户改过 App 名，会多出一个近义标签，需要手动合并（本期不做）。
- **升级是一次性批量写**：58 个分类 + 一次 UPDATE 在同一事务里，`onUpgrade` 期间界面还没起来，不会感知卡顿；但要保证失败可重入（`ensure` 幂等）。
