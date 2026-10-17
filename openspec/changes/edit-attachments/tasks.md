# Tasks

## 1. 详情页

- [x] 1.1 `TransactionDetailPage` 新增可选 `pickImage`：图片区出现「添加图片」方块，选图后调用 `add` 并刷新；`test/pages/transaction_detail_page_test.dart` 用例：加图后计数与缩略图变化、取消选图不变
- [x] 1.2 每张缩略图加 ✕：确认后 `remove` 并刷新；用例：删一张后只剩一张、文件被回收、取消不删
- [x] 1.3 写盘失败/交易不存在时给可读提示且不留下附件记录；用例：注入失败的 picker 或坏路径
- [x] 1.4 明细页与搜索页把 `systemImagePicker()` 传给详情页（Web 为 null）；用例：入口页可构建

## 2. 回归

- [x] 2.1 备份只包含还在用的图片；`test/services/export_service_test.dart` 或新用例：删图后导出，zip 内图片数与详情一致
- [x] 2.2 `flutter analyze` 干净、`flutter test` 全绿（不低于 297 + 新增）
- [x] 2.3 设备端回归：详情页加一张图 → 删掉 → 文件回收；结果写入 tasks.md

## 验证记录（2026-10-18）

- `flutter analyze`：No issues found；`flutter test`：**303 通过**（上一轮 297 + 本次 6）
- 设备端 `integration_test/edit_attachments_flow_test.dart -d emulator-5554`：通过
  - 详情页「图片 · 0」→ 添加图片（注入选图）→ 「图片 · 1」且磁盘多一个文件 → 删掉并确认 → 记录清空、文件回收
- 新增备份一致性用例：删掉一张后导出完整备份，磁盘与记录都只剩一张
- 踩到并记录的两个测试坑：
  1. widget 测试里在 fake async 中 `await` 真实文件 IO 会**永久挂起**（表现为 `flutter test` 卡住、`--timeout` 也不生效）；
     造数据与交互都要放进 `tester.runAsync`
  2. `Positioned` 放在 `Stack` 边界之外（`right: -6`）不接收点击——删除角标点不动就是这个原因，改成 `right: 4`
- 界面计数在删图后的刷新时机在 widget 测试里不稳定（DB 已删、帧未到），所以 widget 用例只断言记录层，
  「计数变化」交给设备端用例验证
## Workflow follow-up

- 归档 change：`openspec archive edit-attachments --yes`
- 归档后回写 `docs/PRODUCT_PLAN.md` §8（M7 状态）与 §14
