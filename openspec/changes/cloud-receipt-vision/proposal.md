# Proposal

## Why

M7「截图记账」现在只有本地 ML Kit OCR：能认字，但对支付截图的排版（图标、按钮文字、
金额与合计混排）噪声很大，且中文模型随 APK 打包，是 F-Droid 等渠道的专有依赖。

决定：**不再使用 OCR，统一改成视觉模型**。

调研结论（2026-10）：

- **Dart 没有可直接用的多厂商兼容层**。最接近的 `langchain`（LangChain.dart）0.9 要求 Dart ≥3.9，
  本项目是 3.6.1；`openai_dart` 11 要求 ≥3.12；`dart_openai` 8 能装，但它只是 OpenAI SDK 封装，
  不解决「一家一家适配」的问题。真正跨厂商的兼容层（LiteLLM、Vercel AI SDK）都在 Python / TS 生态。
- **行业已经收敛到 OpenAI 兼容的 `/chat/completions`**。DeepSeek 官方就是 OpenAI 格式
  （`https://api.deepseek.com`），视觉走 `deepseek-flash`（`deepseek-v4-pro` 不支持视觉），
  图片用 `image_url` 的 base64 data URL；千问 / GLM / Kimi / SiliconFlow / OpenRouter 也都提供兼容端点。
- 所以**只支持 DeepSeek 够用，但不把 DeepSeek 写死**：写一个走 `http` 的 OpenAI 兼容识别器，
  `baseUrl` / `model` 可配置。以后加厂商是改配置，不是加适配代码。

## What Changes

- **删掉本地 OCR**：移除 `google_mlkit_text_recognition` 依赖与 `MlKitReceiptRecognizer`。
  识别只有一条路径——用户配置的视觉模型，不再有「本地兜底」。
- **视觉识别器**：新增 `VisionReceiptRecognizer`，实现现有 `ReceiptRecognizer`。图片转 data URL
  发给视觉模型，提示词只要求「原样输出图中文字」；金额、分类、日期仍由本地 `parseReceiptText`
  解析——规则可测试、可预测，换厂商也不影响解析。
- **默认关闭、显式开启**：设置页「截图记账」区新增云端开关、API Key、服务地址与模型（高级）。
  没开启或没 Key 时完全不识别、也不上传；开启时明确告知「图片会发送给 DeepSeek」。
- **失败只提示，不阻塞**：超时 / 鉴权失败 / 空结果时提示「视觉识别失败，可以手动填」，
  金额与分类保持原样，仍可正常保存。
- **密钥安全**：API Key 存系统安全存储（Android Keystore / iOS Keychain），不进
  `app_state` / SQLite / 日志，也不出现在测试快照里；清除 Key 会自动关闭识别。
- 非目标：截屏自动触发与分享入口（另立 change）、结构化 JSON 提取、多厂商选择 UI、流式输出、
  iOS Share Extension、把图片上传到自建服务、离线识别。

## Capabilities

### New Capabilities

（无）

### Modified Capabilities

- `receipt-recognition`：识别来源从「仅本地 OCR」改为「仅视觉模型、默认关闭」；删除
  「不联网、不上传」的默认承诺，改为「未开启时不上传」；新增「云端识别显式开启」
  「密钥不落库」「OpenAI 兼容协议」「失败不回退、只提示手动填」四条约束。

## Impact

- 删除 `lib/services/ocr/receipt_recognizer_mlkit.dart` 与 `google_mlkit_text_recognition` 依赖
- 新增 `lib/services/ocr/receipt_recognizer_vision.dart`（HTTP 客户端 + 请求/响应）
- 新增 `lib/services/ocr/receipt_vision_settings.dart`（开关、baseUrl、model、API Key 存储）
- 新增 `lib/pages/vision_settings_page.dart`
- `lib/services/ocr/receipt_recognizer_factory.dart`、`lib/pages/shell.dart`：按配置组合视觉识别，
  面板关闭时释放 HTTP 客户端
- `lib/pages/settings_page.dart`：截图记账从 Backlog 改为可用入口 + 状态展示
- `lib/widgets/quick_entry_sheet.dart`：未配置时提示去设置；错误文案改为「视觉识别失败」
- `pubspec.yaml`：新增 `http` 与 `flutter_secure_storage: ^10.3.4`
  （11.x 要求 Dart ≥3.8，不兼容当前工具链）；Android `minSdk` 升到 23（安全存储要求）
- 测试：请求体形状、响应解析、401 / 429 / 5xx / 超时 / 畸形响应、工厂开关组合、设置持久化、
  Key 不落库、面板提示与失败不阻塞
