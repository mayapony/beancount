# Tasks

## 1. 合并前台服务与常驻通知

- [x] 1.1 新增 `CaptureHostService`：一个 Service 内同时起 `captureEntry` 与 `screenshotEntry` 两个 FlutterEngine，保留 `/capture` 与 `/screenshot` 两个通道，`startForeground` 只调一次
- [x] 1.2 通知文案按两个开关组合生成（开/关四态），渠道统一为 `capture_service`，`onDestroy` 里分别 try/catch 清理两个引擎
- [x] 1.3 `CapturePlugin` / `ScreenshotPlugin` 的 `setEnabled` 改为控制同一服务的通道开关；开机恢复只启动一个服务
- [x] 1.4 删除 `CaptureService` / `ScreenshotService` 与清单里对应的 `<service>` 声明，确认 `AndroidManifest` 只剩一个前台服务
- [x] 1.5 测试：两个开关四态下的通知文案与启动/停止行为（原生侧单测或 instrumentation 至少覆盖文案拼装函数）

## 2. 自动入账去重跨批次

- [x] 2.1 `CaptureRuntime` 增加「最近入账记忆」（包名 + 金额 + 时间，存活 `captureMergeWindow`），`_write` 成功后写入，`flush` 时参与合并
- [x] 2.2 `mergeCandidates` 改为按来源区分：通知候选不互并，无障碍 / 截图候选只并进已有候选或记忆
- [x] 2.3 单测：模拟同一页面连续 5 批 flush 提取到同一金额，断言只入账 1 笔
- [x] 2.4 单测：两条同额通知 + 页面候选混合，断言入账 2 笔（通知各成笔）且页面候选不额外成笔
- [ ] 2.5 真机：停在支付成功页 2 分钟，确认只记一笔、只弹一条「已记账」

## 3. 前台失败提示合并与时效

- [x] 3.1 `PendingScreenshotEntry` 增 `expiredAt`/TTL 判定（10 分钟），`_consumePendingScreenshot` 先丢弃过期条目并写一条诊断
- [x] 3.2 本轮剩余条目合并成一条 SnackBar 汇总（含数量与跳转「最近自动记账」），移除逐条 SnackBar 与自动弹记账面板
- [x] 3.3 单测：3 条过期 + 2 条新鲜 → 只弹 1 条汇总、队列清空、过期条目不留提示
- [x] 3.4 单测：只有 1 条新鲜的识别失败时，汇总文案为单数且点击可跳转

## 4. 诊断按来源分流

- [x] 4.1 `CaptureDiagEvent` 增 `channel` 字段与落盘/解析（缺失时按 `kind` 推断），导出报告同步
- [x] 4.2 诊断页加三档切换（全部 / 自动记账 / 截屏识别），空链路显示自己的空状态
- [x] 4.3 单测：老记录（无 `channel`）推断正确；三档过滤结果符合预期

## 5. 门禁

- [x] 5.1 `flutter analyze` 无告警、全量测试绿（`--exclude-tags screenshots`）
- [x] 5.2 debug / release 两种 gradle 构建均可打包
- [x] 5.3 `openspec validate --all --strict` 全绿
- [ ] 5.4 真机回归：通知栏只有一条常驻通知、开关四态正确、截图失败不再逐条弹
