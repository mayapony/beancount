# Tasks

## 1. 解析器（纯函数）

- [x] 1.1 新增 `lib/services/ocr/receipt_parser.dart`：`ReceiptGuess` 与 `parseReceiptText(text, {now})`——金额（合计行优先，否则最大）、日期（三种格式）、分类（关键字表）、备注（店名）、置信度；`test/services/receipt_parser_test.dart` 用例：真实 OCR 噪声文本、合计优先、无合计取最大、`¥`/`元`/千分位、日期三种格式、分类命中与猜不出
- [x] 1.2 边界：空文本、只有数字、超大金额；用例各一条

## 2. 识别器（可插拔）

- [x] 2.1 新增 `ReceiptRecognizer` 接口 + `NoopReceiptRecognizer` + `MlKitReceiptRecognizer`（中文脚本，`TextRecognizer` 用完 close）；条件导入保证 Web 可构建；用例：空实现返回 null、接口可注入
- [x] 2.2 `systemReceiptRecognizer()` 工厂：Web 返回空实现，移动端返回 ML Kit；Android 依赖 `text-recognition-chinese`（已加）

## 3. 面板

- [x] 3.1 记一笔面板接受 `recognizeReceipt`：选图后自动识别（仅当金额为空），结果预填金额/分类/备注/日期，已有输入不覆盖；`test/widgets/quick_entry_sheet_test.dart` 用例：识别结果预填、已有金额不被覆盖、认不出给提示、抛错给提示
- [x] 3.2 `flutter analyze` 干净、`flutter test` 全绿（不低于 303 + 新增）

## 4. 回归

- [ ] 4.1 设备端：用真实小票截图跑 ML Kit → 面板金额=44.50、分类=餐饮；结果写入 tasks.md
- [ ] 4.2 `flutter build apk --release` 通过并记录体积变化

## Workflow follow-up

- 归档 change：`openspec archive receipt-recognition --yes`
- 归档后回写 `docs/PRODUCT_PLAN.md` §8（M7 状态）与 §14
