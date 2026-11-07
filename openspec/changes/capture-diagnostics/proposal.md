# Proposal

## Why

自动记账这条链路目前是黑盒：调用大模型得到的内容（识别结果、生成的规则）在解析后就被丢弃，本地过滤掉了什么、模型原文说了什么都没有留下；后台捕获的每一次判断（无规则、规则未验证、指纹不匹配、提取为空）都只是静默 `return`，唯一的可见痕迹是「入账成功」本身。

结果是两类问题都无法排查：账单信息识别错了，分不清是模型读错还是本地词表/范围把它丢了；自动记账自上线以来一次都没成功执行过，也拿不到任何证据说明断在哪一步。

## What Changes

- **事件流**：捕获链路的每一处决策点都留下一条结构化记录（门未开、抓到树、抓到通知、无规则、规则待定、提取为空、入账、写库失败、识别返回、规则生成返回、学习跳过），含原因与关键字段。
- **双源记录**：Dart 侧写 `app_state`，原生侧写 `SharedPreferences`——引擎未就绪、服务未起、窗口读不到这类最致命的问题发生时 Dart 还不存在，日志必须原生先落；两处同时追加一份 JSONL 到 App 私有目录，便于 adb 取证。
- **模型输出可追溯**：识别事件保留模型原始 JSON，并逐字段标出「模型给的值 / 本地过滤后的值 / 被丢弃的原因」；规则生成事件保留模型原文与实际入库的 DSL、回放验证结果。
- **诊断页**：设置 → 自动记账下新增「诊断记录」，顶部状态卡显示服务状态、规则条数与档位分布、上次捕获/上次入账距今；下方为事件流，可展开看详情。
- **导出**：一键导出诊断报告，可分享也可落成文件；导出默认脱敏（商户名、订单号、长数字），保留金额与指纹——这两项是排查依据。
- 不新增数据库迁移、不新增依赖、不改识别与规则生成协议、不上传任何内容。

## Capabilities

### New Capabilities

- `capture-diagnostics`: 自动记账与截图识别链路的运行记录、诊断页与诊断导出；规定记录哪些决策点、双源存储与环形容量、脱敏边界与保留期限。

### Modified Capabilities

（无。现有 `auto-entry` 与 `screenshot-capture` 的行为要求不变；本变更只增加可观测性，不改变采集、识别与入账的判定结果。）

## Impact

- 新增：`lib/services/capture/capture_diagnostics.dart`（事件模型与存取）、`lib/pages/capture_diagnostics_page.dart`（诊断页与导出）
- 修改：`lib/services/capture/capture_runtime.dart`、`capture_rule_learner.dart`、`capture_rule_generator_cloud.dart`、`lib/services/ocr/receipt_recognizer_vision.dart`、`lib/screenshot_entry.dart`、`lib/capture_entry.dart`（各决策点埋点）
- 修改：`lib/widgets/capture_settings_section.dart`（诊断入口）、`lib/pages/settings_page.dart`、`lib/pages/shell.dart`（跳转接线）
- 修改：`android/.../CaptureRuntime.kt`、`CapturePlugin.kt`、`ScreenshotService.kt`、`ScreenshotPlugin.kt`（原生侧事件与读取通道）、`CapturePrefs.kt`（事件环形）
- 存储：`app_state` 新增 `diag_event:` 前缀的环形键；原生 `SharedPreferences` 新增事件环形；App 私有目录 `diag/` 下新增 JSONL 文件
- 隐私：树快照与模型原文仅落本机，环形容量受限，导出时脱敏；无新增网络请求
