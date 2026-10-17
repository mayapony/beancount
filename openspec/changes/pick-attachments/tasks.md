# Tasks

## 1. 选图与写入

- [x] 1.1 新增 `PickedImage` / `ImagePickSource` / `ImagePickFn` 与基于 `image_picker` 的默认实现（2560 宽、质量 88，文件名带扩展名）；`test/services/image_picker_service_test.dart` 用例：扩展名推断与默认 jpg
- [x] 1.2 新增 `EntryWriter.submit(draft)`：先写交易，`inserted` 为真时逐张调用 `AttachmentRepository.add`，为假时丢弃图片；`test/services/entry_writer_test.dart` 用例：1 张 / 2 张落盘、重复提交不新增附件、文件名非法被拒

## 2. 面板

- [x] 2.1 `QuickEntryDraft` 增加 `images`；面板接 `ImagePickFn`，相册/相机按钮走真实选图，失败给一句提示；`test/widgets/quick_entry_sheet_test.dart` 用例：选图后草稿带 1 张、取消选图不带
- [x] 2.2 缩略图行 + 点击移除 + 按钮角标计数；用例：加两张后移除一张，草稿只剩一张
- [x] 2.3 删除假识别（`_recognizeBill` 与相关状态）；用例：面板不再出现「已识别」文案
- [x] 2.4 Web 上禁用选图并提示；用例：注入 `isWeb: true` 时按钮不可点

## 3. 接线与回归

- [x] 3.1 Shell 用 `EntryWriter` 提交并把默认选图实现注入面板；明细/详情不需要改动（附件链路已在）；用例：入口页能构建
- [x] 3.2 `flutter analyze` 干净、`flutter test` 全绿（不低于 229 + 新增）
- [ ] 3.3 设备端回归：选一张图记一笔 → 明细出现缩略图 → 详情可看大图 → 删除该笔后文件被回收；结果写入 tasks.md

## Workflow follow-up

- 归档 change：`openspec archive pick-attachments --yes`
- 归档后回写 `docs/PRODUCT_PLAN.md` §8（M7 状态）与 §14
