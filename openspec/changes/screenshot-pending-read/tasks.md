# Tasks

> 每个任务完成、验证跑绿后立即原子提交；实现与测试放在同一个提交里。
> 证据（真机日志、截图）写进对应用户可见的说明，不提交 `docs/`。

## 0. 前置

- [x] 0.1 工作区同步到 `origin/main`（落后 24 个提交，截屏链路只在远端）：保留 `docs/review/shots` 的本地改动后 fast-forward；确认 `ScreenshotService.kt`、`ScreenshotWatcher.kt`、`ScreenshotPlugin.kt`、`screenshot_entry.dart` 在本地可读（已完成：`a53b051`）
  - 验证：`git log --oneline -1` 为 `a53b051`；`flutter analyze` 零告警
- [x] 0.2 真机复现基线：连续截 10 张，记录「读取截图失败」次数与首条提示延迟，作为改后对照
  - 证据（改前，01:48 两张）：`media/14066` 发布耗时 2.16s → 读到；`media/14067` 发布 3.60s，App 在 3.0s 放弃 → 「读取截图失败 · 点击手动记」

## 1. 读取等待媒体库发布

- [x] 1.1 `ScreenshotWatcher.projection()` 增加 `IS_PENDING`（API 29+），新增「该条目是否已发布」查询
- [x] 1.2 `ScreenshotService.readCompleteImage()` 改为先查 pending 再 `openInputStream`：pending 时 100ms 轮询等待，不再反复 open；`READ_TIMEOUT_MS` 提到 10s；读成功后保留 `looksComplete()` 与大小校验
- [x] 1.3 日志区分：`等待发布超时` / `读取异常` / `图片损坏`，并记录等待与读取耗时
  - 验证（改后，02:15 真机）：`检测到截图：…_lockscreen.jpg（pending=true）` → `读取截图：等待发布=6813ms 读取=4ms 大小=20KB`；同一张图在旧 3s 上限下必失败，10s 上限下成功

## 2. 去重状态机

- [x] 2.1 `ScreenshotWatcher` 增加 `inFlight` 集合；`emit()` 不再提前写 `processed`；改为读取成功后 `processed.add` + 持久化
- [x] 2.2 读取失败/超时后释放 `inFlight` 且不写 `processed`，允许发布后的二次回调重试
  - 验证：`emit()` 只在成功路径落盘；失败路径 `markHandled(readSucceeded=false)` 只释放 in-flight

## 3. 检测即反馈

- [x] 3.1 新建通知渠道 `screenshot_alert`：`IMPORTANCE_HIGH` + `setSilent(true)` + 无振动；旧 `screenshot_result` 保留不再使用
- [x] 3.2 在检测回调最前面发进度通知「已截屏 · 识别中…」，保证先出提示再读图
- [x] 3.3 结果原地更新同一 ID：`已自动记账 ¥X` / `没认出金额 · 点击手动记` / `读取截图失败 · 点击手动记`；等待期间不出现失败态
  - 验证（02:15 真机）：检测 `40.318` → 进度通知 `40.319`（IsOngoing=true）；同一 ID `42` 在 `48.300` 变结果；`screenshot_alert` 渠道 `mImportance=4`、`mSound=null`、`mVibrationEnabled=false`

## 4. 失败可补偿

- [x] 4.1 读取失败时把 URI 记到 `ScreenshotPrefs`，通知 intent 带 `EXTRA_RECOVER_SCREENSHOT`
- [x] 4.2 `ScreenshotPlugin` 处理该 extra：重新读 URI → `copyToCache` → `sharedImageAvailable`；读不到时返回空
- [x] 4.3 Dart 侧复用分享链路消费；取不到图时给一句前台提示，不静默
  - 验证：编译通过 + 代码走查；「点通知取回」未在真机复现（MIUI 上程序化截屏不可靠，见 5.1 的人工清单）

## 5. 验收

- [ ] 5.1 小米连续截 10 张：识别 10/10、首条提示 ≤ 1s、记录最长等待发布时长
  - 已测 1 张：首条提示延迟 1ms、等待发布 6813ms（成功）。余下 9 张待人工连拍复测
- [ ] 5.2 三星/华为各 3 张（有设备时），确认 10s 上限够用
- [ ] 5.3 关闭开关：服务停止、常驻通知消失、之后截屏无提示无上传
- [x] 5.4 门禁：`flutter analyze` 零告警、`flutter test --exclude-tags screenshots` 521 全绿、`assembleDebug` / `assembleRelease` 构建成功、`openspec validate --all --strict` 24/24 通过
  - 网络代理 127.0.0.1:7897 不可用，Gradle 用 `--offline` 跑缓存依赖
- [ ] 5.5 归档前回写 spec 与 `docs/PRODUCT_PLAN.md` 的工作队列
