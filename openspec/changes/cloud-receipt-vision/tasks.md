# Tasks

## 1. 配置与密钥

- [x] 1.1 `ReceiptVisionSettings`：`enabled`、`baseUrl`（默认 `https://api.deepseek.com`）、`model`（默认 `deepseek-flash`），读写 `app_state`；空值/坏值回落默认；尾部斜杠归一化；单测覆盖默认值、往返、坏值与归一化
- [x] 1.2 `ReceiptApiKeyStore` 抽象：`SecureReceiptApiKeyStore`（系统安全存储）+ `MemoryReceiptApiKeyStore`；单测确认 Key 只走安全存储，不写 `app_state`
- [x] 1.3 `pubspec.yaml` 增加 `http` 与 `flutter_secure_storage: ^10.3.4`（11.x 要求 Dart ≥3.8）；Android `minSdk = 23`；`flutter pub get` 通过

## 2. 视觉识别器

- [x] 2.1 请求构造：`POST {baseUrl}/chat/completions`，`Authorization: Bearer`，`model`，文本提示 + `image_url` data URL（MIME 由文件头推断），关闭 thinking，`max_tokens` 限制；单测断言 URL、Header、JSON 形状、尾部斜杠归一化、Key 不进请求体
- [x] 2.2 响应解析：200 取 `choices[0].message.content`；空内容/无 choices 返回 null；401/403/429/5xx/超时/网络异常/畸形 JSON 抛 `ReceiptRecognitionException`（消息可读且不含 Key）；单测覆盖
- [x] 2.3 提示词固定为「原样输出图中文字，不要解释/总结」；用假 HTTP 响应验证输出交给 `parseReceiptText` 后金额、分类、备注正确

## 3. 删除本地 OCR

- [x] 3.1 移除 `google_mlkit_text_recognition` 依赖与 `MlKitReceiptRecognizer`；Android/iOS 不再打包中文 OCR 模型
- [x] 3.2 `systemReceiptRecognizer()` 改为视觉单路径：关闭 / 无 Key / Web → null；开启 + 有 Key → `VisionReceiptRecognizer`；单测覆盖四种组合与「改配置立即生效」
- [x] 3.3 `shell.dart` 每次打开面板前异步读取配置并注入；面板关闭后 `close()` 释放 HTTP 客户端；支持注入内存 Key 存储（测试/截图脚本）

## 4. 设置界面

- [x] 4.1 新增 `VisionSettingsPage`：云端开关、Key 输入（掩码、已保存状态、可清除）、服务地址与模型（高级，可恢复默认）；关闭时提示「图片不会离开设备」，开启时提示「图片会发送给 DeepSeek」
- [x] 4.2 设置页「截图记账」从 Backlog 改为可用入口，并按「已开启 / 缺 Key / 未开启」显示状态
- [x] 4.3 交互测试：默认关闭；开启但无 Key 时提示且不生效；保存后生效；清除 Key 自动关闭；Key 不回显；高级保存与恢复默认
- [x] 4.4 面板提示：未配置时提示去设置；识别失败提示「视觉识别失败，可以手动填」且不阻塞保存

## 5. 文档与回归

- [x] 5.1 更新 `docs/PRODUCT_PLAN.md` M7 与 README/DESIGN：识别改为视觉模型（默认关闭），不再提本地 OCR
- [x] 5.2 `flutter analyze` 零告警、`flutter test` 全绿、`openspec validate cloud-receipt-vision --strict` 通过
- [ ] 5.3 真机用真实 Key 识别一张支付截图，记录金额/分类是否命中；失败场景（错 Key、断网）确认提示可读且仍能手动保存

## Workflow follow-up

- 归档 change：`openspec archive cloud-receipt-vision --yes`
- 归档后回写 `docs/PRODUCT_PLAN.md` §8（M7 状态）与 §11（截屏自动触发仍是待决策项）
