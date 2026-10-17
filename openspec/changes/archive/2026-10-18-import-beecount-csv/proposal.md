# Proposal

## Why

用户在 BeeCount 里积累了真实账本（导出为 CSV），换到金豆后不可能手抄一遍。没有导入能力，这个 App 只能从零开始记，历史数据等于沉没；而导入的数据如果被"猜错分类、重复写入、丢金额精度"，比不导入更糟。

## What Changes

- 新增 **从 BeeCount 导出文件导入**：读取 `beecount_*.csv`（UTF-8 BOM、12 列），逐行解析为交易；支持选择含附件包的完整备份 `.zip`。
- 分类 **自动创建并保留原名**（含二级分类），同名复用已有分类（与本地种子重名的直接复用，不重复建）；账户、标签同理，新账户初始余额为 0。
- 只导入**收入 / 支出**；转账行跳过并计入报告（当前数据层没有转账模型）。
- **附件原样搬运**：从附件包取出 `images/*.jpg` 写入私有目录并关联到交易，同一文件多笔共享；缺图只记警告不中止。
- 复用 `add-local-storage` 的**去重键**：同一文件重复导入不产生重复账目（幂等）。
- 导入**先预览后写入**：展示将导入条数、将新建的分类/账户/标签、将跳过的行数与原因、图片张数与体积。
- 导入结束生成**结果报告**：成功 / 跳过 / 失败，失败精确到行号与原因；单行错误不中止整批。
- 入口放在 `设置 → 数据管理 → 从 BeeCount 导入`，不占用主流程。

不包含：币种换算（非 CNY 行按原币种金额导入并标记）、图片压缩/OCR、一键导出回 BeeCount。

## Capabilities

### New Capabilities

- `data-import`: 从 BeeCount 导出的 CSV 读取、字段映射、去重、预览与导入报告。

### Modified Capabilities

（无：本变更只新增导入行为，不改动 `ledger-storage` / `ledger-taxonomy` 的既有要求。分类与账户"自动创建"复用的是 `ledger-taxonomy` 已定义的新增能力。）

## Impact

- 依赖 `add-local-storage` 先落地（模型、仓储、去重键、分类数据化、附件仓储）。
- 新增依赖：CSV 解析（`csv`）、压缩包解压（`archive`）与文件选择（`file_picker`）。
- 代码：新增 `lib/services/import/`（解析、解包、映射、写入、报告）与导入预览/结果页面；`settings_page.dart` 增加入口。
- 数据：首次导入会批量新增分类/账户/标签/图片；不删除、不覆盖已有数据。
- 验收素材：用户自己导出的 `beecount_*.zip`，放 `test/fixtures/local/`（**已 gitignore，真实账本数据不进 git**）；git 内只放 `test/fixtures/beecount_sample*.csv` 这类脱敏样本。
