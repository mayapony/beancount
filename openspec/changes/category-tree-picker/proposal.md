# Proposal

## Why

两件事卡在一起：

1. **两级分类录不进去**。数据库和分类管理页早就支持两级（`categories.parent_id`，最多两级），但「记一笔」面板只渲染一级（`_visibleCategories` 过滤掉了 `parentId != null` 的），所以「打车」「停车费」这类二级分类只能靠编辑已有账被动出现，新建时选不到。
2. **大模型只看得见 6 个分类**。识别提示词用的是硬编码的 `kCategoryKeywords`（餐饮/交通/购物/医疗/娱乐/旅行），而用户账本里有 12 个种子分类加自建分类（如「日用品」）。模型给不出「日用品」，只能返回 `null`，最后落到「其他」——真机上今天两笔自动账就是这么变「其他」、再被用户手动改回去的。

## What Changes

- **两级选择器**：记一笔面板的分类区改成「一级横排 + 选中后展开其二级」；空二级的一级直接点选即可。每层都能「新增」。
- **分类树进提示词**：识别提示词不再用硬编码列表，改用账本里的真实分类树（一级 + 二级），二级名也参与匹配。
- **缺分类就新建**：识别出的分类在账本里不存在时，按现有 `AutoCreatePolicy` 的配额（单笔 ≤1、7 天 ≤3、总数 ≤40、开关关闭不建）自动建一个；后台自动入账路径同样适用。
- 落库时优先落二级 id；统计仍按一级汇总、二级下钻。
- 不改表结构（两级是既有能力），只改读取与展示。

## Capabilities

### New Capabilities

（无）

### Modified Capabilities

- `ledger-taxonomy`: 新增「记一笔面板 SHALL 支持两级分类选择与逐层新增」的行为要求。
- `receipt-recognition`: 分类词表改为来自账本真实分类树，并允许在配额内新建缺失分类。
- `auto-entry`: 后台自动入账 SHALL 复用同一套分类树解析与新建配额。

## Impact

- `lib/widgets/quick_entry_sheet.dart`：分类区分两段式，新增加二级与新增入口
- `lib/services/ocr/receipt_recognizer_vision.dart`、`receipt_recognizer_factory.dart`：提示词接收分类树
- `lib/services/screenshot/auto_entry.dart`、`lib/services/capture/capture_entry_saver.dart`：后台路径接分类树与新建配额
- 无需数据库迁移；`categories.parent_id` 已存在
