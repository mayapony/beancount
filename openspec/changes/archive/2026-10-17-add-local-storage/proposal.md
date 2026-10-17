# Proposal

## Why

App 目前只有演示数据：`记一笔` 提交后只弹一条 SnackBar，明细 / 洞察 / 资产三个页面全部读 `lib/data/demo_data.dart` 的常量。要从 BeeCount 导入真实账本，必须先有一个能写、能读、能约束重复的本地数据层——否则导入的数据无处落地，也无法验证"导进来对不对"。

## What Changes

- 新增**本地持久化**：交易、分类、账户、标签、附件五类数据落库，App 重启后仍在。
- **BREAKING**：分类从写死的 12 个（`BeanColors.categoryNames` + 数组下标引用）改为**可编辑数据**。记一笔的分类网格、明细行、图表都改为按分类记录渲染，支持一级/二级分类与任意数量。
- `记一笔` 提交真正写库；明细、洞察、资产改为从库里读取（不再读 demo 常量）。
- 记住**上次使用的分类 / 账户 / 类型**，从库里最近一条记录读取，而不是进程内变量。
- 交易增加**去重键**（时间 + 金额 + 备注 的规范化组合），为后续 CSV 导入做幂等保证。
- 金额以**整数分**存储，避免浮点误差。
- 首次启动写入**默认种子**：12 个支出分类 + 6 个收入分类（收入页不再复用支出分类）、1 个初始余额为 0 的默认账户，保证空库也能正常记账。
- 新增**记账凭证图片**：交易可带 0..N 张图，文件落应用私有目录，库里只存文件名（同一文件可被多笔引用）。

不在本变更范围：云同步、多币种换算、转账记录、CSV 导入本身（导入是下一个独立变更）。

## Capabilities

### New Capabilities

- `ledger-storage`: 账本数据的本地持久化、读取、金额精度与去重键。
- `ledger-taxonomy`: 分类 / 账户 / 标签作为用户可维护的数据，以及首次启动的默认种子。

### Modified Capabilities

（无：项目此前没有已归档的 spec。）

## Impact

- 新增依赖：本地数据库 `drift` + `sqlite3_flutter_libs`、代码生成 `build_runner` / `drift_dev`、附件目录 `path_provider`，需要一次 `flutter pub get`。
- 代码：新增 `lib/data/` 下的模型与仓储（含 `AttachmentRepository`）；改造 `lib/pages/transactions_page.dart`、`insights_page.dart`、`assets_page.dart`、`lib/widgets/quick_entry_sheet.dart`、`lib/widgets/common.dart`（`CategoryAvatar` 从"下标"改为"分类记录"）。
- `lib/data/demo_data.dart` 保留，降级为种子数据来源与 UI 预览用。
- 权限/平台：附件写入应用私有目录，不需要存储权限；Android / iOS 必达，Web 仅需不崩溃（内存库）。
- 后续依赖：`import-beecount-csv` 变更依赖本次落地的模型、去重键与分类数据化。
