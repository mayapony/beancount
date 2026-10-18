# Tasks

## 1. 配置与密钥

- [ ] 1.1 新增 `ReceiptVisionSettings`：`enabled`、`baseUrl`（默认 `https://api.deepseek.com`）、`model`（默认 `deepseek-flash`），读写 `app_state`；损坏或缺失值回落到默认；单测覆盖默认值、往返、坏值
- [ ] 1.2 新增 `ReceiptApiKeyStore` 抽象：安全存储实现 + 测试用内存实现；单测确认 Key 只走安全存储，不写 `app_state`
- [ ] 1.3 `pubspec.yaml` 增加 `http` 与 `flutter_secure_storage: ^10.3.4`（11.x 要求 Dart ≥3.8）；`flutter pub get` 与 Android 构建通过

## 2. DeepSeek 识别器

- [ ] 2.1 请求构造：`POST {baseUrl}/chat/completions`，`Authorization: Bearer`，`model`，文本提示 + `image_url` data URL（MIME 由扩展名推断），关闭 thinking，限制输出长度；单测用 `MockClient` 断言 JSON 形状、默认值归一化（尾部斜杠等）与不泄露 Key
- [ ] 2.2 响应解析：200 取 `choices[0].message.content`；空内容返回 null；401/429/5xx/超时/畸形 JSON 抛 `ReceiptRecognitionException`（消息可读且不含 Key）；单测覆盖
- [ ] 2.3 提示词固定为「原样输出图中文字，不要解释/总结」；用假 HTTP 响应验证输出交给 `parseReceiptText` 后金额、分类、备注正确

## 3. 组合与回退

- [ ] 3.1 识别器组合：开启且已存 Key → 云端优先；云端抛错或空文字 → 回退本地 ML Kit；关闭/无 Key/Web → 现有本地或空实现；单测验证调用顺序与「云端成功就不调用本地」
- [ ] 3.2 `shell.dart` 在打开记账面板前异步读取配置并注入；设置变更后下一次记账立即生效；widget 测试覆盖开/关两条路径

## 4. 设置界面

- [ ] 4.1 「截图记账」区从 Backlog 改为可用入口：云端开关、Key 输入（掩码、已保存状态、可清除）、服务地址与模型（高级，可恢复默认）；关闭时提示「图片不会离开设备」，开启时提示「图片会发送给 DeepSeek」
- [ ] 4.2 交互测试：默认关闭；开启但无 Key 时给出提示且不生效；保存后生效；清除 Key 自动关闭；Key 不回显

## 5. 文档与回归

- [ ] 5.1 更新 `docs/PRODUCT_PLAN.md` M7 与 README 状态：云端识别为可选、默认本地；不删除「默认不上传」的承诺
- [ ] 5.2 `flutter analyze` 零告警、`flutter test` 全绿、`openspec validate cloud-receipt-vision --strict` 通过
- [ ] 5.3 真机用真实 Key 识别一张支付截图，记录金额/分类是否命中；失败场景（错 Key、断网）确认回退本地且可保存

## Workflow follow-up

- 归档 change：`openspec archive cloud-receipt-vision --yes`
- 归档后回写 `docs/PRODUCT_PLAN.md` §8（M7 状态）与 §11（截屏自动触发仍是待决策项）
