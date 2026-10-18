# Tasks

## 1. 匹配与解析（纯 Dart，先写失败测试）

- [x] 1.1 新增 `lib/services/ocr/entry_matching.dart`：`normalizeName`（空白/标点/全半角/大小写）、分类词表与别名、标签词表、账户别名表，以及 `matchCategory` / `matchAccount` / `tagCandidates`；用例覆盖别名命中、归一化重名、账户只做相等/包含匹配；`flutter test test/services/ocr/entry_matching_test.dart` 全绿
- [x] 1.2 扩展 `ReceiptGuess` 与 `parseReceiptText`：新增 `tagNames` 与 `accountName`（词表驱动，认不出为空），保持金额/日期/分类规则不变；`flutter test test/services/receipt_parser_test.dart` 全绿并新增标签/账户用例
- [x] 1.3 新增 `lib/services/ocr/auto_create_policy.dart`：读 `app_state` 的配额时间戳，判定单笔 ≤1 分类 / ≤2 标签、7 天 ≤3 分类 / ≤10 标签、分类总数 ≤40、开关关闭时不建；用例覆盖配额边界与回滚（不写库）；`flutter test test/services/ocr/auto_create_policy_test.dart` 全绿

## 2. 记一笔面板接入（Dart UI）

- [x] 2.1 `QuickEntrySheet` 增加「初始识别结果 / 待识别图片 / 以识别中状态打开」入参，复用 `_applyReceipt` 的预填逻辑（只补空字段）；Widget 用例：直接带入结果、带图进入后自动识别、已有输入不被覆盖；`flutter test test/widgets/quick_entry_sheet_test.dart` 全绿
- [x] 2.2 面板展示标签 chip 与「将新建分类：X」候选，保存时才调用 `CategoryRepository.ensure` / 标签创建并受 `AutoCreatePolicy` 约束，取消不动库；Widget 用例：候选展示、保存落库、取消零写入、标签上限 2；同上测试文件全绿

## 3. 设置项与待处理结果

- [x] 3.1 设置页新增「截屏自动识别」「允许自动新建分类/标签」（默认关）与权限状态说明，偏好写入 `app_state`；Widget 用例覆盖默认关、开启后显示权限引导、拒绝后回退；`flutter test test/pages/settings_page_test.dart` 全绿
- [x] 3.2 实现 `pending_screenshot_entry` 的读写与消费：冷启动/恢复时读取、`LockGate` 解锁后由 `Shell` 打开面板、消费后清除；用例覆盖「已锁 → 解锁后才弹」「重复启动不重复弹」；`flutter test test/pages/shell_update_test.dart` 与新增用例全绿

## 4. Android 截屏检测

- [x] 4.1 `AndroidManifest.xml` 增加 `READ_MEDIA_IMAGES` / `READ_EXTERNAL_STORAGE(maxSdk 32)` / `POST_NOTIFICATIONS` / `FOREGROUND_SERVICE(_SPECIAL_USE)`、`specialUse` service 声明与用途属性；`flutter build apk --debug` 通过，`aapt dump permissions` 能看到声明的权限
- [x] 4.2 新增 `ScreenshotWatcher.kt`：注册/注销 MediaStore `ContentObserver`，按 `RELATIVE_PATH`（29+）/`DATA`（<29）+ 文件名关键字判定截图，10 秒时间窗 + 指纹去重；设备端用 `adb shell` 触发系统截屏，日志显示只处理一次
- [x] 4.3 新增 `ScreenshotService.kt`（前台服务）：`specialUse` 类型、常驻低优先级通知、启停与 `START_STICKY`、开机广播恢复；设备端验证开关打开后通知常驻、关闭后通知消失且不再触发
- [x] 4.4 建立平台通道（service ↔ headless engine ↔ UI）：注册 `GeneratedPluginRegistrant`、`screenshot_entry` 命名入口、事件回传与错误兜底；设备端验证通道能收发，`flutter analyze` 干净

## 5. 后台识别与通知

- [x] 5.1 headless 引擎内复用 `systemReceiptRecognizer` 完成识别并写 `pending_screenshot_entry`，识别失败/无 Key 时写失败原因；设备端用 `MockClient` 跑 `integration_test/screenshot_entry_flow_test.dart`，验证结果 JSON 与面板预填
- [x] 5.2 进度/结果通知：识别中原地更新为「已识别 ¥X · 点击记账」或失败文案，`PendingIntent` 带 `pending_entry_id`；设备端验证通知内容与点击后进入面板（应用锁开启时先解锁）

## 6. 分享入口（Android）

- [x] 6.1 `MainActivity` 增加 `ACTION_SEND` + `image/*` intent-filter 与 `onNewIntent` 处理，把图片交给 Dart 走同一识别链路；设备端从相册分享一张小票截图，验证面板预填

## 7. 端到端验收

- [ ] 7.1 真机三条路径验收并记录到本文件「验证记录」：后台截屏（微信/相册截图）→ 通知 → 点击 → 预填；前台截屏 → 应用内提示；关闭开关 → 无任何反应
- [x] 7.2 降级路径验收：拒绝相册权限、拒绝通知权限、视觉未配置三种情况均不崩溃、不上传，并给出可读提示
- [x] 7.3 跑全量门禁：`flutter analyze` 零告警、`flutter test --exclude-tags screenshots` 全绿、`flutter build apk --debug` 通过、`openspec validate --all --strict` 通过

## Workflow follow-up

- 归档前把「验证记录」写进本文件（命令、通过数、真机型号与结果）。
- `openspec archive screenshot-auto-entry`，并把 `docs/PRODUCT_PLAN.md` M7 状态与 §11 风险表更新为已完成。

## 验证记录（2026-10-18）

- 环境：`emulator-5554`（API 36，x86_64）debug APK；本机无 macOS，iOS 未验证。
- `flutter analyze` → No issues found；`flutter test --exclude-tags screenshots` → **495 通过**；`flutter build apk --debug` → 通过；`openspec validate --all --strict` → 23 passed。
- `integration_test/screenshot_entry_flow_test.dart -d emulator-5554` → 通过：MockClient 冒充视觉模型 → 解析 → 写 pending JSON → 启动面板预填 44.50 并清空。
- 设备端链路（模拟器）：
  - 触发方式：`adb screencap` 生成 `Pictures/Screenshots/*.png` 并插入 MediaStore；`ScreenshotWatcher` 日志 `检测到截图：...`。
  - 后台：常驻通知「正在监听截屏」；检测后结果为「金豆 · 截屏记账 / 没认出金额 · 点击手动记」（未配置 API Key 的降级路径），`pending_screenshot_entry` 写入含临时图片路径；点通知打开 App，pending 被消费并提示「截屏识别失败，可以手动记一笔」。
  - 前台：App 可见时同一路径不触发（无日志、pending 不增加）。
  - 关闭：开关置 false 并重启后，服务与两条通知都消失，截屏不再触发。
  - 降级：撤销 `READ_MEDIA_IMAGES` 后不崩溃、无 pending；撤销 `POST_NOTIFICATIONS` 后识别仍写 pending（通知不展示）。
  - 分享：`am start -a android.intent.action.SEND -t image/png` 交付到金豆，面板打开并附上图片、显示「识别中…」。
- `flutter build apk --release` → 67.4 MB；release（AOT）下 headless 入口同样可解析，通知与降级路径正常。
- 未覆盖：真实系统截屏键（用 adb 写 MediaStore 模拟）、真实视觉 API 成功识别（无可用 Key，成功路径由 MockClient 覆盖）、多厂商截图目录差异（仅 AOSP 模拟器）、真机（7.1 保留未勾选）。
