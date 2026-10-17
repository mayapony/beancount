# Design

## 数据流：先在面板里"待定"，提交时才落盘

```
点相册/相机 → image_picker 返回 bytes → 面板持有 PendingImage（内存里）
提交 → EntryWriter：
   1. TransactionRepository.create（含去重）
   2. inserted == false → 丢弃图片，返回"已存在"
   3. inserted == true  → 逐张 AttachmentRepository.add(transactionId, bytes, fileName)
```

为什么不在选图时就落盘：那样关闭面板或保存失败都会留下孤儿文件；附件目录只有"已保存的账"才配拥有文件。
这也是既有 `sweepOrphans()` 的设计前提（它只做兜底，不该是常规路径）。

## 文件名

`<micros>_<seq>.<ext>`，扩展名从 picker 返回的 name 推断（默认 `jpg`）。落盘前经 `AttachmentRepository._sanitize` 去掉路径分隔符——已有约束，不重复实现。

## 可注入的选图

```dart
class PickedImage { final Uint8List bytes; final String fileName; }

typedef ImagePickFn = Future<PickedImage?> Function(ImagePickSource source);
enum ImagePickSource { gallery, camera }
```

- 默认实现用 `image_picker` 的 `pickImage(source:, maxWidth: 2560, imageQuality: 88)`：先压一道，避免 12MP 原图进库。
- 测试注入假实现（返回固定 bytes 或 null 模拟取消），不碰平台通道。
- Web：`kIsWeb` 时面板禁用入口并提示（附件链路依赖 `dart:io`，Web 侧本来就没有可写目录）。

## 界面

```
[金额卡]
¥ 38.50
[缩略图 40×40] [缩略图 40×40]            ← 已选图片，点一下移除
点击填写备注                       🖼  📷  🏷
```

- 图片按钮角标显示已选数量（`🖼 2`），避免用户忘了自己选过图。
- 缩略图行只在有图时出现，不加空占位（与明细/详情的规则一致）。
- 删除假识别：`_recognizeBill` 与 `_recognizing` 一并移除，`image_picker` 的耗时用按钮上 200ms 的 loading 表达即可。

## 关键决策

| 决策 | 选择 | 理由 |
|---|---|---|
| 何时落盘 | 提交时 | 选图即落盘会留下孤儿；提交时写才符合"这笔账存在才有图" |
| 去重命中时 | 丢弃图片 | 账没新增，图也不该多出来；返回"已存在"提示 |
| 是否压缩 | 是（2560 宽、质量 88） | 票据认清即可，原图几 MB 会让备份包爆炸 |
| 编辑时能否加图 | 本轮不做 | 编辑路径要先支持"删除已有附件 + 新增"，单独一轮 |
| 假识别按钮 | 删除 | 留着会让用户以为有 AI；M7 真做时再回归 |

## 风险

| 风险 | 应对 |
|---|---|
| 相机权限被拒 | picker 抛错 → 面板一句「无法打开相机，请检查权限」，不影响记账 |
| 大图导致卡顿 | 选图时压缩；写入在提交路径里异步完成，不阻塞键盘 |
| Web 误点 | 入口禁用 + 说明文案 |
| 图片写到一半失败 | 交易已存在、部分附件已写：附件按引用计数管理，用户可在详情页看到已写入的那几张；`sweepOrphans` 兜底清理无引用的文件 |
