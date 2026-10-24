# Proposal

## Why

真机日志（小米，Android 17，v1.1.6）显示：截屏后金豆经常弹「读取截图失败 · 点击手动记」，但同一张图手动上传/分享却能识别。根因不在识别，而在**读取时机**——MIUI 先在 MediaStore 插一条 pending 行，非属主 App 打不开；App 只等 3 秒，而实测发布要 2.2–4.7 秒。

更糟的是反馈：检测到截屏后只有 3 秒「识别中」，然后直接跳失败；用户在最需要确认「这次截到没有」的那几秒里，看到的是一条错误。

## What Changes

- **读取等待发布**：读取前先查 `IS_PENDING`，pending 就等，不再当读取失败；等待上限 10 秒，期间保持「识别中」。
- **检测即反馈**：检测到截屏的那一刻就出「已截屏 · 识别中…」，不等文件可读。用高优先级静默渠道，能立刻瞥见但不响铃、不振动。
- **去重状态机**：只有读取成功才把该截图记为已处理；并发回调与发布后的二次回调都去重，不重复识别、不重复记账。
- **失败可补偿**：等待超时仍读不到时，点通知把这张图重新取出来（此刻通常已发布）走分享链路，而不是空点一下。
- 不改识别协议、不新增设置项、不新增数据库表。

## Capabilities

### New Capabilities

（无）

### Modified Capabilities

- `screenshot-capture`: 「识别状态可见」细化为「检测即提示、等待发布期间不显示失败、失败有补偿入口」；新增「截屏读取 SHALL 等待媒体库发布」与去重时机要求。

## Impact

- `android/app/src/main/kotlin/com/jindou/bean_count/ScreenshotService.kt`：读取等待、通知渠道与文案、失败 URI 记录
- `android/app/src/main/kotlin/com/jindou/bean_count/ScreenshotWatcher.kt`：已处理标记从「检测到」挪到「读成功」
- `android/app/src/main/kotlin/com/jindou/bean_count/ScreenshotPlugin.kt`：点失败通知时重新读取并交给 Dart（复用分享链路）
- `lib/pages/shell.dart`、`lib/services/screenshot/`：失败图取不到时的一句前台提示
- **前置**：本地工作区落后 `origin/main` 24 个提交（截屏记账整套功能只在远端），apply 前必须先同步，否则这些文件不存在
- 无数据库迁移；无新增权限；旧 `screenshot_result` 渠道保留，兼容已安装用户
