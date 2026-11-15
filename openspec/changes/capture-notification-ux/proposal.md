# Proposal

## Why

真机诊断日志（1869 条运行记录，11-07 至 11-15）暴露了三个互相叠加的问题：同一个 App 挂着两条常驻通知（自动记账 + 截屏监听），用户不知道它们各自在干什么；截图识别失败被逐条塞进底部黑条延迟播报（72 次截图识别中 44 次没认出金额），而成功那一路本来就有系统通知；同一笔支付被重复入账（小米商城 ¥299 在 17 分钟内记了 4 次，每次都弹一条「已记账」），因为 120 秒合并窗口只在单次 flush 内生效。诊断记录又把自动记账与截屏识别两类事件混在一条时间线里，排查时看不出某条记录属于哪条链路。

## What Changes

- **合并后台常驻为一条通知**：把「自动记账监听」与「截屏监听」两个前台服务合并成一个前台服务，只保留一条常驻通知，文案按实际开启的通道动态生成。**BREAKING**：系统通知渠道从两个减为一个，已安装设备上旧渠道会留在系统设置里不再使用。
- **自动入账去重跨 flush 生效**：把「同包名 + 同金额 + 120 秒」的合并从「单次 flush 批次内」提升为「跨批次有效」，停在支付成功页不再每次重抓都记一笔。
- **截图识别失败不再逐条弹**：底部黑条只在「需要用户当场补救」时出现且最多一条汇总；纯识别失败改为静默留痕（诊断记录可见），待处理项加 10 分钟时效，过期直接归档不再播报。
- **诊断记录按来源分流**：事件带上来源（自动记账 / 截屏识别），诊断页可切换只看一条链路，默认仍可看全部。

## Capabilities

### New Capabilities

（无）

### Modified Capabilities

- `auto-entry`: 常驻通知由两条合并为一条；自动入账去重 MUST 跨多次 flush 生效，同一页面停留期间同一笔支付只记一次。
- `screenshot-capture`: 识别失败的提示 SHALL 合并为单条汇总并带时效，MUST NOT 逐条排队弹出。
- `capture-diagnostics`: 运行记录 SHALL 标明来源链路，诊断页 SHALL 支持按「自动记账 / 截屏识别」分流查看。

## Impact

- 原生侧：`android/app/src/main/kotlin/com/jindou/bean_count/CaptureService.kt`、`ScreenshotService.kt`、`ScreenshotBootReceiver.kt`、`CapturePlugin.kt`、`AndroidManifest.xml`（两个前台服务合成一个，通知渠道与 id 变更）
- 捕获链路：`lib/services/capture/capture_runtime.dart`（去重记忆跨批次）、`capture_candidate.dart`（窗口常量）、`capture_diagnostics.dart`（事件新增来源字段）
- 前台消费：`lib/pages/shell.dart`（`_consumePendingScreenshot` 的提示策略）、`lib/services/screenshot/pending_entry.dart`（时效）
- 诊断界面：`lib/pages/capture_diagnostics_page.dart`、`lib/services/capture/capture_diag_export.dart`
- 依赖：无新增第三方依赖；`app_state` 里新增的字段走已有序号前缀，无 schema 迁移
