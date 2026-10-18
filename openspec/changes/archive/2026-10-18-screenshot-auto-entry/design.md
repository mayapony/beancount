# Design

## Context

见 `proposal.md`；这里只记录影响实现方式的现状与硬约束。

- Flutter 3.27.3，`minSdk 23`、`targetSdk 35`；单库 `AppDatabase`（`NativeDatabase.createInBackground`），`app_state` 是现成的键值表，更新模块已用它存偏好（`update_preferences.dart`）。
- 识别链路已就绪且可插拔：`ReceiptRecognizer` / `systemReceiptRecognizer` / `VisionReceiptRecognizer`，面板里 `_applyReceipt` 负责预填；API Key 在 `flutter_secure_storage`。
- 平台通道先例：`UpdateInstaller.kt`（MethodChannel，`MainActivity.configureFlutterEngine` 注册）。
- 应用锁 `LockGate` 用整树替换（不是路由），所以「点通知 → 解锁 → 弹面板」必须走「先解锁、再消费待处理结果」。
- 平台硬事实（已核对）：
  - Android 14+ 的 `Activity.ScreenCaptureCallback` 只在**本 App 界面可见**时触发，覆盖不了「在微信里截图」。
  - Android 全版本可用的是 `ContentObserver` 监听 `MediaStore.Images`，需要媒体读权限（33+ `READ_MEDIA_IMAGES`，≤32 `READ_EXTERNAL_STORAGE`）。
  - 进程被回收后监听即失效；`targetSdk 35` 下 `dataSync` 前台服务每 24 小时限 6 小时。
  - iOS 只有 `userDidTakeScreenshotNotification`（App 挂起后收不到），没有后台方案。

## Goals / Non-Goals

**Goals:**

- 后台可靠感知系统截屏，并把截图立刻交给现有 Dart 识别器（不复制识别逻辑）。
- 识别结果落到分类 / 标签 / 账户，且「新建」是显式、可取消、有配额的。
- 后台与前台都有清晰状态（识别中 / 已识别 / 失败），点一下就能记账。
- 不新增数据库表、不做数据迁移。

**Non-Goals:**

- iOS 后台检测与 iOS 分享扩展（本机无 macOS 构建环境，单独立项；期间 iOS 维持手动选图）。
- 本地 OCR、自动入账、多账本。
- 对截图内容做「是不是小票」的预筛：检测到就上传，由识别置信度决定提示文案。

## Decisions

### D1 检测机制：自写 Kotlin ContentObserver，全版本统一走 MediaStore

不用 pub 上的截屏插件：`flutter_screenshot_detector` 在 Android 14+ 只走 `ScreenCaptureCallback`，恰好覆盖不了核心场景；旧插件已停更。官方回调也不采用——它只在金豆可见时触发，而那种情况下我们按要求忽略自身截图。

做法：`ScreenshotWatcher.kt`（前台服务内）对 `MediaStore.Images.Media.EXTERNAL_CONTENT_URI` 注册 `ContentObserver(notifyForDescendants = true)`，变更时查询最新一行，按 `RELATIVE_PATH`（API 29+）/`DATA`（<29）+ `DISPLAY_NAME` 关键字判定是否截图。

- 备选：`focusHeuristic`（要求 App 在前台，不可用）；`FileObserver`（路径与权限更差，厂商差异更大）。

### D2 前台服务：`specialUse` + 常驻通知

`FOREGROUND_SERVICE` + `FOREGROUND_SERVICE_SPECIAL_USE`，service 声明 `android:foregroundServiceType="specialUse"` 与 `PROPERTY_SPECIAL_USE_FGS_SUBTYPE`（值说明「监听系统截屏以生成记账草稿」）。常驻通知用低优先级渠道，文案「正在监听截屏 · 点此设置」，点按进设置。`START_STICKY` + 开机广播恢复。

- 备选：`dataSync`（`targetSdk 35` 下 6 小时上限，不可持续）；`mediaProcessing`（同样限时）。

### D3 识别执行位置：服务内 headless FlutterEngine，结果写 `app_state`

服务持有一个独立 `FlutterEngine`（named entrypoint `screenshot_entry.dart`，`@pragma('vm:entry-point')`），复用 Dart 侧 `systemReceiptRecognizer` / `parseReceiptText` / 匹配逻辑；识别结果写入 `app_state` 的 `pending_screenshot_entry`（JSON），由 Kotlin 发「已识别」通知。UI 引擎冷启动或恢复时读取该键、弹面板、随后删除。

- 备选 A：缓存主引擎（`FlutterEngineCache`）供服务复用——要让 `MainActivity` 改用 cached engine，改变启动路径与插件绑定时机，风险更大。
- 备选 B：Kotlin 里重写 HTTP 与解析——与可插拔识别器冲突，还会形成第二套解析规则。
- 备选 C：点通知后才识别——违背「检测即上传」的决策。

### D4 去重、限流与自身截图

- 指纹 = `MediaStore id + DATE_ADDED`；进程内互斥 + `app_state` 记录最近指纹（10 秒窗口），重复通知直接丢弃。
- 只处理 `DATE_ADDED` 距现在 ≤ 10 秒、且路径/文件名命中截图特征的记录。
- 10 秒窗口同时充当限流：连续截图只处理第一张。
- App 的 Activity 处于 resumed 时不处理（避免截自己的界面）；用 `ActivityLifecycleCallbacks` 维护前台标志。

### D5 上传时机与开关

新增设置项「截屏自动识别」（默认关闭）。开启时：申请相册读权限 + 通知权限 → 启动服务。视觉识别（开关 + Key）已启用时，检测到截图立刻上传识别；未启用时只发「已截屏」通知，不上传、不识别。

### D6 分类 / 标签 / 账户匹配与受限创建

- 新文件 `lib/services/ocr/entry_matching.dart`：`normalizeName`（去空白/标点、全半角、大小写）、分类词表、标签词表、账户别名表；纯函数，便于单测。
- 分类：归一化 + 别名命中已有分类则直接预选；未命中生成「候选新建」。
- 标签：从词表取命中项，最多 2 个；已有同名即复用。
- 账户：只做「归一化后相等 / 包含」匹配（微信、支付宝、云闪付、银行卡尾号），MUST NOT 用编辑距离；匹配不到沿用上次账户。
- 创建只发生在保存时，由 `AutoCreatePolicy` 检查配额：单笔 ≤1 个分类、≤2 个标签；滚动 7 天 ≤3 个分类、≤10 个标签；分类总数 ≤40；开关默认关闭。配额记录放 `app_state`（时间戳数组），不新增列。
- 备选：给 `categories`/`tags` 加 `auto_created` 列——需要迁移，且对回滚不友好，暂不采用。

### D7 面板扩展

`QuickEntrySheet` 增加「初始识别结果 / 待识别图片 / 以识别中状态打开」三个可选入参，内部仍复用 `_applyReceipt`；新增标签 chip 与「将新建：X」标记。取消或关闭面板不写任何分类/标签。

### D8 通知与路由

通知渠道 `screenshot_auto_entry`。三条通知：常驻（service）、进度（静默、原地更新）、结果（默认优先级）。结果通知的 `PendingIntent` 带 `pending_entry_id`；冷启动由 `MainActivity` 读取并传给 Dart，`LockGate` 解锁后由 `Shell` 消费并打开面板，消费后清除，避免重复弹。

### D9 分享入口（仅 Android）

`MainActivity` 增加 `ACTION_SEND` + `image/*` 的 intent-filter；`onNewIntent` 把图片 URI 交给 Dart，走与自动检测相同的识别 → 预填链路。iOS 不新增扩展。

### D10 权限与降级

开启开关时按版本申请 `READ_MEDIA_IMAGES` / `READ_EXTERNAL_STORAGE`、`POST_NOTIFICATIONS`。拒绝相册权限则开关回退为关并说明原因，提供「去系统设置」；拒绝通知权限则识别结果只在下次打开 App 时以应用内提示展示。记录「已询问过」，不重复弹系统框。

### D11 测试策略

- 纯 Dart 单测：`normalizeName`、别名匹配、配额计算、去重指纹、`ReceiptGuess` 新增字段解析。
- Widget 测试：面板预填分类/标签/账户、「将新建」标记、取消不落库、标签上限（内存 drift + 假识别器）。
- Integration（设备）：用平台通道注入「新截图」事件，验证 识别 → 通知/面板 链路；真实按键截屏作为人工验收记录写进 `tasks.md`。
- 门禁不变：`flutter analyze` 零告警、`flutter test --exclude-tags screenshots`、`flutter build apk --debug`、`openspec validate --all --strict`。

## Risks / Trade-offs

- 常驻服务耗电与内存（双 Flutter 引擎）→ 默认关闭；开关即停服务；`specialUse` 文案透明；真机观察后再决定是否需要更激进的省电策略。
- 相册权限等于「读取所有照片」→ 开启前有明确说明；拒绝时用分享入口兜底。
- 双引擎各开一个 drift 连接 → 后台只写一条 pending 与配额记录，冲突面小；失败时降级为「识别失败，点击手动」。
- 厂商截图目录/命名差异 → 路径 + 文件名双条件；验收覆盖小米/华为/三星至少各一台（人工清单）。
- 每张截图都上传的成本与隐私 → 仅视觉启用时上传；通知明示；可随时关闭。
- 非小票截图 → 置信度低时只提示「没认出金额」，绝不自动入账。
- Android 后台启动限制（Android 12+）→ 服务只从用户开启开关或开机广播启动，不从后台任意拉起。
- 自身截图判定依赖 Activity 生命周期 → 分屏/多窗口边界可能漏判，接受。

## Migration Plan

- 无数据库迁移；新增设置项默认关闭，首次开启时走权限引导。
- 回滚：关闭开关会停服务、撤常驻通知；已自动创建的分类/标签保留，用户可在分类管理里删除。卸载无残留（后台只写 `app_state`）。
- 发版前校验：`flutter analyze`、`flutter test --exclude-tags screenshots`、`flutter build apk --debug`、`openspec validate --all --strict`。

## Open Questions

- 连续截图的冷却是否要从 10 秒延长到更长（等真机观察误报率后再定，不影响本期实现）。
- iOS 分享扩展单独立项的时间点。
