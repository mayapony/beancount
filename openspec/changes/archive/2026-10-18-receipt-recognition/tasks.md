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

- [x] 4.1 设备端：用真实小票截图跑 ML Kit → 面板金额=44.50、分类=餐饮；结果写入 tasks.md
- [x] 4.2 `flutter build apk --release` 通过并记录体积变化


## 验证记录（2026-10-18）

- `flutter analyze`：No issues found；`flutter test`：**320 通过**（上一轮 303 + 本次 17）
- 设备端 `integration_test/receipt_ocr_flow_test.dart -d emulator-5554`：通过
  - 真实中文小票截图（内联 base64，避开设备上的相对路径）→ ML Kit 输出
    `金豆餐厅消费小票 / 牛内面 ¥38.50 / 可乐 / 合計 / ¥6.00 / ¥44.50 / 2026-10-18 12:30`
  - 解析出 **44.50 / 餐饮 / 金豆餐厅**，面板预填后提交的草稿金额 44.5、分类「餐饮」、备注「金豆餐厅」
- release：`flutter build apk --release` 通过，**45.7 MB**（上一轮 25.5 MB，中文模型 +20MB）
  - 装到模拟器能正常启动（桌面/明细页可用）
  - 后续可做：`--split-per-abi` 拆包，或把识别改成按需下载模型

## 过程中踩的三个坑

1. **中文模型不在插件里**：只加 `google_mlkit_text_recognition` 会在运行时
   `ClassNotFoundException: ChineseTextRecognizerOptions$Builder`，必须在 `android/app/build.gradle`
   显式 `implementation 'com.google.mlkit:text-recognition-chinese:16.0.0'`。
2. **release 的 R8 会报缺类**：插件源码顺手引用了日文/韩文/天城文的识别类，而我们只依赖了中文包；
   在 `proguard-rules.pro` 里 `-dontwarn/-keep com.google.mlkit.vision.text.**` 放行即可。
3. **金额正则贪婪顺序**：`\d{1,3}(?:,\d{3})*|\d+` 会把 `2026` 切成 `202`+`6`，
   于是日期行被当成 202.00 的金额。改成 `\d+(?:,\d{3})*` 并过滤 4/6 位无小数点的年份与单号，
   用真实 OCR 文本做的用例才守住这个边界。

## Workflow follow-up

- 归档 change：`openspec archive receipt-recognition --yes`
- 归档后回写 `docs/PRODUCT_PLAN.md` §8（M7 状态）与 §14
