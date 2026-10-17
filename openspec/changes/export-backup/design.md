# Design

## 数据出口：直接复用导入的格式

导出的 CSV/zip 不是"另设一套格式"，而是**照抄导入端的约定**——这样往返闭环由格式本身保证，不需要一条转换链路：

| 环节 | 约定来源 |
|---|---|
| 表头与列序 | `lib/services/import/bee_count_csv.dart` 的 `_headerAliases` |
| 时间格式 | 导入端 `parseBeeCountTime` 接受 `YYYY-MM-DD HH:mm:ss` |
| 金额 | 整数分 → `(cents / 100).toStringAsFixed(2)`（不做浮点运算） |
| 标签/附件分隔 | 导入端 `_splitMulti` 按 `,` 切分并去重 |
| 附件包 | 导入端从 zip 里取第一个 `.csv` 与第一个 `.tar.gz`，图片在 tarball 的 `images/` 下 |

所以只要"写"与"读"对齐，`导出 → 清库 → 导入` 就是一条可测的闭环。

## 数据形状

新增 `TransactionRepository.exportRows()`，一次装配好导出需要的全部字段，避免页面上 N+1 查询：

```dart
class ExportRow {
  final Transaction transaction;
  final List<String> categoryPath; // [一级] 或 [一级, 二级]
  final String? accountName;
  final List<String> tags;
  final List<String> attachmentNames;
}
```

- 分类路径由 `parentId` 还原；父分类不存在时退化为「一级 = 自己」。
- 附件名取 `attachments.file_name`（磁盘上的真实文件名，CSV「附件」列与 tarball 内文件名一致）。
- 排序：按发生时间升序（与 BeeCount 导出习惯一致，导入端不依赖顺序）。

`AttachmentRepository.allFiles()` 供备份打包使用：遍历附件目录，按文件名去重（同一张图可能被多笔账引用，包里只放一份）。

## 生成与保存

```
ExportService
  ├─ buildCsv()    → ExportFile(fileName, bytes, entryCount, imageCount)
  └─ buildBackup() → ExportFile(...)   // csv + tar.gz → zip
```

- 全部在内存里构造成 `Uint8List`：账本量级（几百笔 + 几十 MB 图片）可接受；真到 GB 级再改成流式写临时文件。
- 保存走 `FilePicker.platform.saveFile(fileName:, bytes:)`（系统 SAF/另存为对话框）：
  - 返回 null = 用户取消 → 页面恢复原状，不提示成功、不写任何文件；
  - 抛异常 → 显示可读原因，页面可重试。
- **不做「先写临时文件再 move」**：`saveFile` 本身是原子的单次写入，失败时由系统丢弃。

## 页面

设置 →「导出」进入 `ExportPage`：

```
本月概览之外：48 笔账 · 46 张图 · 约 18.8 MB
[导出 CSV]        小、可回灌、不含图片
[完整备份 zip]    含全部图片，可换机
（完成后）✓ 已导出 beancount_backup_20261018_011500.zip · 18.7 MB · 下载
```

- 打包期间按钮禁用 + 一行进度文案（"正在打包 46 张图片…"），避免重复点击。
- 失败文案固定格式：`导出失败：<原因>`，不吞异常。

## 关键决策

| 决策 | 选择 | 理由 |
|---|---|---|
| 备份格式 | zip（csv + tar.gz） | 与 BeeCount 完整备份同构：本 App 能导入、BeeCount 也能导入 |
| 是否压缩图片 | 否（原样打入 tar.gz） | 图片已是压缩格式，二次压缩收益低、耗时高 |
| 保存位置 | 系统保存对话框 | Android 11+ 无法直接写公共目录；SAF 是唯一"用户可见"的合法路径 |
| CSV 是否带 BOM | 带 | Excel/WPS 打开中文表头不乱码，且导入端会剥掉 |
| 导出范围 | 全部账目（不分月） | 「备份」语义就应该是全量；按月导出留给后续 change |
| 图片去重 | 按文件名 | 同图共享机制本身以文件名为键 |

## 风险

| 风险 | 应对 |
|---|---|
| `saveFile` 在部分 Android ROM 上行为不一致 | 失败要有可读提示；真机回归里直接验证一次导出到「下载」 |
| 大量图片时内存峰值 | 先按现状实现；若实测 > 200MB，改成流式写临时文件再交给 SAF |
| 导出期间数据被改（例如同时记账） | 打包读取的是同一事务快照之外的实时数据，允许轻微不一致；备份是"某一刻"的快照，不追求强一致 |
