# Proposal

## Why

M7 的标题是「截图记账（自动）」，但目前只完成了一半：用户必须自己打开金豆、点「记一笔」、选一张图，识别才会发生。真实场景里用户是在微信/支付宝/银行 App 里截完图就离开，回到金豆再找图是多余动作。识别器已经是可插拔接口，缺的只是「截屏被感知」这一环。

## What Changes

- **截屏感知（Android）**：常驻前台服务监听 MediaStore 新截图，检测到即读取；同一张截图的多次回调去重；本 App 自身界面的截图不触发。前台服务用常驻通知说明用途，用户可随时关闭。
- **检测即识别**：视觉识别已启用（开关 + API Key）时，检测到截图**立刻上传识别**，不再二次确认；未启用时只发通知，不上传、不识别。
- **识别中 → 结果**：后台用通知（「已截屏 · 识别中…」→「已识别 ¥44.50 · 点击记账」），前台用应用内提示；点击后（必要时先解锁）打开记一笔面板并预填。
- **分类落点**：识别出的分类名先归一化（去空格/标点/全半角）再按别名匹配已有分类；匹配不到时，**只在用户点保存时**按受限词表新建一级支出分类——单笔最多 1 个、7 天最多 3 个、总数上限 40、默认关闭、不建二级分类、不建收入分类。
- **自动打标签**：从固定词表（咖啡、外卖、打车、超市、微信支付……）生成标签候选，单笔最多 2 个；标签同样只在保存时创建；同名/近似名复用。
- **账户只匹配不创建**：从文本里的支付线索匹配**已有**账户名称，匹配不到沿用上次账户；MUST NOT 自动建账户。
- **兜底入口（Android）**：系统分享面板把截图分享到金豆，覆盖拒绝常驻通知的用户；走同一条识别 → 预填链路。
- **设置与权限**：截屏自动识别开关、自动新建分类/标签开关（默认关）、相册读取与通知权限引导；关闭自动识别后不再上传。

非目标：iOS 后台截屏检测（系统不提供）；iOS 分享扩展（本机无 macOS 构建环境，后续单独立项，期间 iOS 维持手动选图）；本地 OCR；自动入账（仍由用户确认后保存）；多账本。

## Capabilities

### New Capabilities

- `screenshot-capture`: 截屏检测的触发源（Android 前台服务 + MediaStore、分享入口）、去重与节流、通知与权限边界

### Modified Capabilities

- `receipt-recognition`: 触发时机从「选图后」扩到「检测到截屏后立即识别」，识别结果新增分类/标签/账户的匹配与预填行为
- `ledger-taxonomy`: 新增自动创建分类与标签的克制规则（词表、配额、时机）；账户 MUST NOT 被自动创建

## Impact

- 新增 Android 原生：前台服务 + ContentObserver + 平台通道（照 `UpdateInstaller.kt` 的 MethodChannel 风格）、通知渠道；`AndroidManifest.xml` 增加权限与 service 声明
- 新增 Dart：`lib/services/screenshot/`（通道、去重、调度、通知文案）、`lib/services/ocr/`（账户/标签候选）
- 改动：`lib/widgets/quick_entry_sheet.dart`（初始识别结果、标签、新建分类确认）、`lib/pages/shell.dart`（注入与冷启动路由）、`lib/pages/settings_page.dart`、`lib/services/ocr/receipt_parser.dart`
- 数据：复用 `app_state` 存已处理截图指纹与新建配额，不新增表
- 权限：`READ_MEDIA_IMAGES`（33+）/ `READ_EXTERNAL_STORAGE`（≤32）、`POST_NOTIFICATIONS`（33+）、`FOREGROUND_SERVICE` + `specialUse` 类型与用途声明
- 测试：解析器/匹配/配额纯逻辑单测、面板预填与标签 Widget 测试、设备端真机截屏链路（IntegrationTest）
- 风险：厂商截图目录差异导致漏检；常驻服务被系统回收；非小票截图带来误报与云端调用成本；相册读权限的用户信任成本
