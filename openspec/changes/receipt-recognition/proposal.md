# Proposal

## Why

M7 的标题是「截图记账（自动）」：现在能选图、能存图，但**图里的金额和商家没有变成一笔账**。
这一块做完，M7 就从"半个功能"变成"拍一张小票 → 确认一下 → 入账"。

## What Changes

- **本地识别（离线）**：用 ML Kit 的中文文字识别在设备上读小票，不联网、不上传图片。
- **把文字变成账**：一个小而确定的解析器——优先取「合计/实付/应付」那一行的金额，否则取最大金额；顺带认日期与商家，
  并按关键字猜分类（餐厅/面馆→餐饮，超市→购物，打车/地铁→交通……）。
- **预填而不是直接入账**：识别结果填进记一笔面板（金额、分类、备注、日期），用户确认后才保存；没认出金额时明说「没认出金额」。
- **可插拔**：`ReceiptRecognizer` 接口 + ML Kit 实现；测试与 Web 注入替身或直接关闭。
- 非目标：多栏表格重建、手写体、外币小票（识别出金额后仍按当前账户币种记）、离线模型下发的进度 UI。

## Capabilities

### New Capabilities

- `receipt-recognition`: 小票截图 → 本地文字识别 → 金额/分类/日期/备注的预填与用户确认

### Modified Capabilities

（无：记一笔的字段与落库语义不变，识别只是替用户填。）

## Impact

- 新增 `lib/services/ocr/receipt_parser.dart`（纯函数：文字 → `ReceiptGuess`）
- 新增 `lib/services/ocr/receipt_recognizer.dart` + 平台实现（条件导入，Web 用空实现）
- `lib/widgets/quick_entry_sheet.dart`：选图后自动尝试识别，结果预填 + 一句反馈
- `lib/pages/shell.dart`：注入 ML Kit 识别器
- `android/app/build.gradle`：显式依赖 `text-recognition-chinese`（插件不自带中文模型）
- 测试：解析器（真实 OCR 噪声文本）、面板预填、设备端真实识别
