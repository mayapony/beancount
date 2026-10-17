# Tasks

## 1. 详情页

- [x] 1.1 `TransactionDetailPage` 新增可选 `pickImage`：图片区出现「添加图片」方块，选图后调用 `add` 并刷新；`test/pages/transaction_detail_page_test.dart` 用例：加图后计数与缩略图变化、取消选图不变
- [x] 1.2 每张缩略图加 ✕：确认后 `remove` 并刷新；用例：删一张后只剩一张、文件被回收、取消不删
- [x] 1.3 写盘失败/交易不存在时给可读提示且不留下附件记录；用例：注入失败的 picker 或坏路径
- [x] 1.4 明细页与搜索页把 `systemImagePicker()` 传给详情页（Web 为 null）；用例：入口页可构建

## 2. 回归

- [ ] 2.1 备份只包含还在用的图片；`test/services/export_service_test.dart` 或新用例：删图后导出，zip 内图片数与详情一致
- [ ] 2.2 `flutter analyze` 干净、`flutter test` 全绿（不低于 297 + 新增）
- [ ] 2.3 设备端回归：详情页加一张图 → 删掉 → 文件回收；结果写入 tasks.md

## Workflow follow-up

- 归档 change：`openspec archive edit-attachments --yes`
- 归档后回写 `docs/PRODUCT_PLAN.md` §8（M7 状态）与 §14
