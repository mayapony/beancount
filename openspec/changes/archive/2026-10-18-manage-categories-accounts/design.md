# Design

## 数据层

### 分类

| 方法 | 语义 |
|---|---|
| `rename(id, name)` | 追加同层级重名校验：`findByName(name, type, parentId) != this` → 抛 `DuplicateCategoryNameException` |
| `updateAppearance(id, {color, icon})` | 只改样式，不动名称与层级 |
| `moveBy(id, delta)` | 同类型同级内上移/下移：与相邻项交换 `sortOrder`（不重排整表，避免写放大） |
| `usageCounts()` | 一次 `GROUP BY category_id` 得到「分类 id → 笔数」，页面不做 N+1 |
| `migrateAndDelete(fromId, toId)` | 事务内：`UPDATE transactions SET category_id = toId WHERE category_id = fromId` → 删除该分类及其无引用的子分类 |

约束保持：目标分类必须同类型；`fromId != toId`；已有子分类被引用时拒绝（与 `delete` 一致）。

### 账户

| 方法 | 语义 |
|---|---|
| `create({name, type, initialBalanceCents})` | 名称唯一（同名直接复用会掩盖错误，这里抛 `DuplicateAccountNameException`）；id 用 `acc-<micros>-<seq>`，**不再由名称推导**——否则改名会改掉主键 |
| `update(id, {name, type, initialBalanceCents})` | 改名同样查重；类型与期初余额直接写 |
| `delete(id)` | 有交易引用 → 抛 `AccountInUseException(count)` |
| `usageCount(id)` | `COUNT(*) FROM transactions WHERE account_id = ?` |

> `ensure(name)` 保留原名派生 id 的行为（导入幂等依赖它）；新增/改名走显式 id，两条路径互不影响。

## 界面

### 分类页（`CategoriesPage`）

```
[支出] [收入]                              ← 胶囊切换（与洞察页同款）
[+] 新建
─────────────────────────────
餐饮                12 笔   ›
  外卖               3 笔   ›
交通                 8 笔   ›
```

- 点行 → 编辑面板（底部），字段：名称、图标（12 个候选）、位置（上移/下移）、操作（保存 / 删除）。
- 新建：同一面板，额外多一个「父分类」选择（默认「无（一级分类）」）。
- 删除被引用：弹「迁移到…」面板，列出同类型其它分类（排除自身与自身子级），确认后迁移 + 删除。
- 排序按钮在编辑面板里（上移/下移），不做拖拽：两级列表的拖拽在 Flutter 里语义容易含糊，按钮更明确、可测试。

### 账户页（`AccountsPage`）

```
钱包            钱包 · 6 笔        ¥1,240.55   ›
招商银行卡      储蓄卡 · 12 笔     ¥28,560.00   ›
```

- 点行 → 编辑面板：名称、类型（钱包/储蓄卡/信用卡/其他）、期初余额、保存 / 删除。
- 期初余额输入用 `TextField + 数字键盘`，落库前换算成整数分（`parseAmountToCents` 复用导入端的解析）。
- 删除被引用 → 就地提示「有 12 笔交易在使用该账户，先迁移再删除」，不弹迁移（账户迁移是另一件事，见非目标）。

## 关键决策

| 决策 | 选择 | 理由 |
|---|---|---|
| 排序交互 | 编辑面板里的上移/下移 | 二级列表拖拽语义模糊；按钮可测、无手势冲突 |
| 分类删除 | 支持迁移 | 既有 spec 已承诺「迁移或取消」，这一轮把它做实，避免 spec 漂移 |
| 账户删除 | 不提供迁移，只拒绝 | 迁移账户会改余额归属，属于记账操作，不适合藏在「管理」里 |
| 新账户 id | 时间戳 + 序号 | 原名派生 id 在改名时会破坏主键稳定性 |
| 页面拆两个 | 分类页 + 账户页 | 两类数据的字段与操作差别大，合并成一页要加分段 + 两套表单，反而更绕 |

## 风险

| 风险 | 应对 |
|---|---|
| `moveBy` 在同 `sortOrder` 数据上可能不生效 | 交换前先按 (sortOrder, name) 稳定排序取邻居；用例覆盖重复 sortOrder |
| 迁移到自身子级形成环 | 目标列表排除自身与 `childrenOf(self)` |
| 删除父分类时子分类仍有引用 | 逐个子分类检查，命中即拒绝并说明是哪个子分类 |
