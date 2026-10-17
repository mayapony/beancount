# Proposal

## Why

数据进得来、出不去：导入把 48 笔真实账目和 46 张票据搬进了金豆，但设置里的「导出」还是 `M8` 占位。
Android 11+ 访问不到 `Android/data/`，换设备、换 App 都只能靠这一个出口——现在这个出口是空的。

## What Changes

- **导出 CSV**：按 BeeCount 导出的同一套表头与格式写出全部账目（含二级分类、账户、标签、附件名），保证「导出后能再导入回来」。
- **完整备份 zip**：一个包内含 `beecount_<时间戳>.csv` 与 `beecount_attachments_<时间戳>.tar.gz`（`images/` 下是全部票据原件），与 BeeCount 完整备份同构——既能被本 App 重新导入，也能交给 BeeCount。
- **保存到用户选的位置**：调用系统保存对话框（SAF/下载目录），用户取消则不落任何文件；写失败给出可读原因，不留半成品。
- **导出页**：设置 →「导出」，显示将导出多少笔账 / 多少张图，两种格式各一个按钮，完成后显示文件名、大小与保存位置。
- 非目标：Excel（xlsx）、云端上传/分享面板、按时间范围筛选导出、导入端的支付宝/微信账单。

## Capabilities

### New Capabilities

- `data-export`: 把本地账本导出为可回灌的 CSV，以及含图片的完整备份包；保存位置、取消与失败的处理

### Modified Capabilities

（无：导入侧行为不变，本次只是复用它的格式约定。）

## Impact

- 新增 `lib/services/export/export_service.dart`、`bee_count_csv_writer.dart`、`lib/pages/export_page.dart`
- `lib/data/repositories/transaction_repository.dart`：新增 `exportRows()`（带分类路径 / 账户名 / 标签 / 附件文件名）
- `lib/data/repositories/attachment_repository.dart`：新增 `allFiles()`（备份打包用）
- `lib/pages/settings_page.dart`：把「导出」从 `M8` 占位改成真实入口
- 复用依赖：`csv` + `archive` + `file_picker`（不新增第三方包）
- 测试：CSV 往返、zip 往返、导出页 widget test；真机回归「导出→清库→导入」闭环
