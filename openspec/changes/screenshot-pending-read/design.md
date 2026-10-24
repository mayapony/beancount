# Design

## Context

见 `proposal.md`。这里记录真机证据与影响实现方式的硬约束。

### 真机证据（2026-10-25 01:48，小米 25113PN0EC / Android 17 / v1.1.6）

同一台设备、同样操作，两张截图的 MediaStore 发布延迟不同，结果就不同：

```text
14066（成功）
  27.223  插入 media/14066（pending）
  27.301  首次 openInputStream -> IllegalStateException
  29.382  MediaUtils: Published entry      ← 发布耗时 2.16s
  29.548  读到 359KB -> 压缩 110KB -> 识别

14067（失败）
  39.089  插入 media/14067（pending）
  39.102  Watcher「检测到截图」，立刻写入 processed
  39.109  首次读 -> 同一个异常，之后每 100ms 重试
  42.183  3 秒到点，放弃                  ← 截止线
  42.687  MediaUtils: Published entry      ← 发布耗时 3.60s，只差 504ms
  42.419  通知：读取截图失败 · 点击手动记
```

异常原文：

```text
java.lang.IllegalStateException: Only owner is able to interact with
pending/trashed item content://media/external/images/media/14067
itemOwner = com.miui.screenshot  callingPackageName = com.jindou.bean_count
```

### 现状代码（`origin/main`）

- `ScreenshotService.readCompleteImage()`：`READ_TIMEOUT_MS = 3_000L`、`READ_POLL_MS = 100L`，反复 `openInputStream` 直到超时；超时返回 null → 「读取截图失败」。
- `ScreenshotWatcher.emit()`：**先** `processed.add(uri)` + 落盘 SharedPreferences，**再**交给服务读图。
- `ScreenshotService.processRecognize()`：读失败直接 return，没有调用 Dart 侧，因此没有任何待确认记录；通知却写「点击手动记」。
- 通知：`screenshot_result` 渠道（IMPORTANCE_DEFAULT），进度与结果共用 ID 42，`showProgress()` 已有「已截屏 · 识别中…」。

### 平台事实

- Android 11+：`IS_PENDING=1` 的媒体条目只有属主（这里是 `com.miui.screenshot`）能打开，其它 App `openInputStream` 抛 `IllegalStateException`。查询（`ContentResolver.query`）不受此限，能读到行与 `IS_PENDING`。
- 发布延迟由厂商截图流程决定：本机实测 2.16s 与 3.60s；同一设备不同截图也会差一倍。
- 通知渠道的重要性在创建后**不可由代码提升**，想从「默认」升级到「悬浮提示」只能新建渠道 ID。
- 后台服务不能弹 Toast；要「立刻察觉」只能用通知。

## Goals / Non-Goals

**Goals:**

- 截屏在 pending 态也有即时、可察觉的反馈，用户不用等 3 秒才知道有没有截到。
- 常规厂商（发布 < 5s）下不再出现「读取截图失败」。
- 失败不再是死路：点通知能把这张图取回来。
- 同一张图只识别一次，不重复记账。

**Non-Goals:**

- 不改识别协议、prompt、解析规则与自动入账策略。
- 不为 iOS 做后台截屏（系统不提供）。
- 不引入 Kotlin 单测基建（`android/app/src/test` 目前不存在，新增测试源集会拉高构建改动面）；本轮用设备端集成测试 + 真机验收覆盖。
- 不追求「发布瞬间」的精确事件：没有公开 API，等待 + 轮询仍是唯一手段。

## Decisions

### D1 读取等待发布：先查 `IS_PENDING`，再 open

- `projection()` 增加 `MediaStore.Images.Media.IS_PENDING`（API 29+；< 29 无此列，保持原逻辑）。
- `readCompleteImage()` 每轮先 query 该 URI：`IS_PENDING=1` 就 `sleep(100ms)` 继续，**不去 openInputStream**；`=0` 再读字节。
- 这样轮询不再产生 30 条 `IllegalStateException` 系统日志，也让「还在写」与「真读不到」在日志里可区分。
- 上限 `READ_TIMEOUT_MS` 从 3s 提到 **10s**：本机最慢 4.7s，留一倍余量；仍读不到才算失败。
- 读到后保留 `looksComplete()`（JPEG EOI / PNG IEND）与 `expected` 大小校验，避免拿到半张图。
- 备选：只把 3s 改成 10s（不改查询）。否决——日志噪音大、失败原因不可区分，且发布后仍可能读到半截。

### D2 检测即反馈：进度通知提前到检测回调，并换成可瞥见的渠道

- `ScreenshotWatcher.emit()` 之后立刻 `showProgress()`（现在在 `processRecognize()` 开头，语义等价，但挪到检测回调最前面，保证「先出提示，再读图」）。
- 新建渠道 `screenshot_alert`：`IMPORTANCE_HIGH` + `setSilent(true)` + `setVibrate(null)`，只做视觉悬浮（heads-up），不响铃不振动。
- 进度与结果继续共用 `RESULT_ID = 42`，原地更新：`已截屏 · 识别中…` → `已自动记账 ¥X` / `没认出金额 · 点击手动记` / `读取截图失败 · 点击手动记`。
- 等待发布期间文案保持「识别中」，MUST NOT 先显示失败再改回来。
- 旧渠道 `screenshot_result` 保留但不再使用（已安装用户的历史通知不受影响；渠道不可删除是系统行为）。
- 备选：沿用 DEFAULT 渠道。否决——DEFAULT 不会悬浮，正是「不跟手」的来源。
- 备选：用声音/振动提醒。否决——每张截图都响太吵；静默悬浮已足够「立刻察觉」。

### D3 去重状态机：读成功才写 processed

- `ScreenshotWatcher` 维护两个集合：`inFlight`（进程内，防并发重复）与 `processed`（跨进程持久化）。
- `emit()`：`processed` 或 `inFlight` 命中就丢弃；否则加入 `inFlight` 并回调。
- 读取成功并交给识别后：`processed.add` + 持久化，`inFlight.remove`。
- 读取失败/超时后：`inFlight.remove`，**不写** `processed`（写入交给 D4 的失败记录），这样发布后的二次回调仍有机会重试。
- 备选：只靠 `processed`。否决——就是现在的 bug：一次瞬时失败永久拉黑这张图。

### D4 失败可补偿：点通知把图取回来

- 读取失败时，`ScreenshotService` 把该 URI 记到 `ScreenshotPrefs`（`last_failed_uri`），并把「点击手动记」的 `PendingIntent` 换成带 `EXTRA_RECOVER_SCREENSHOT` 的 intent。
- `MainActivity` 收到该 extra → `ScreenshotPlugin` 读这个 URI（此时通常已发布）→ `copyToCache` → 设 `pendingSharedImagePath` → 发 `sharedImageAvailable`。
- Dart 侧复用现有分享链路 `_consumeSharedImage()`：打开记一笔面板 → 走同一条识别 → 预填。取不到时给一句前台提示（`这张图暂时读不到，可以直接手动记`），而不是无反应。
- 这样「读取截图失败 · 点击手动记」不再是空点，也不用给失败图单独造一套待确认队列。
- 备选：写入 `app_state` 的 pending 队列（Dart 侧）。否决——失败时连图字节都没有，pending 记录只能存 URI，还要新增一种「无图 pending」状态与消费分支；复用分享链路改动更小。

### D5 日志与可观测

- 成功：`检测到截图 uri=… 等待发布=1234ms 读取=180ms 原图=359KB`。
- 失败：区分 `等待发布超时`（10s 仍 pending）/ `读取异常`（其它异常）/ `图片损坏`（`looksComplete` 为假）。
- 保留现有 `识别图片：原图 …KB，识别图 …KB`。

### D6 测试与验收

- 设备端集成测试（扩展 `integration_test/screenshot_entry_flow_test.dart`）：通道注入「截图事件 → 识别结果写库 → 面板预填」链路，不依赖真实厂商行为。
- 真机验收（写进 `tasks.md` 的证据区）：小米连续截 10 张，成功率 10/10；首条提示出现时间 ≤ 1s；等待发布最差 ≤ 5s。
- 门禁不变：`flutter analyze` 零告警、`flutter test --exclude-tags screenshots`、`flutter build apk --debug`、`openspec validate --all --strict`。

## Risks / Trade-offs

- **串行队列变长**：10s 等待会让后排截图延迟（现有 `ioExecutor` 是单线程，为的是避免 429）。缓解：常规发布 < 5s；超时只在异常场景发生。
- **静默悬浮仍可能被嫌吵**：用户可在系统设置里把该渠道降级；文档不承诺一定悬浮。
- **高优先级渠道创建后不可回退**：若反馈观感不好，只能再建新渠道 ID，旧渠道会留在系统设置里。
- **失败补偿依赖文件还在**：用户删了截图就只能空面板；此时提示要说清楚。
- **厂商差异**：华为/三星/OPPO 的发布延迟未实测，10s 是保守值，不保证覆盖极端情况。

## Migration Plan

- 无数据库迁移；无设置项变化。
- 通知渠道新增 `screenshot_alert`，旧 `screenshot_result` 保留不动。
- 回滚：读取改回 3s、通知改回旧渠道即可，不涉及数据。

## Open Questions

- 10s 是否覆盖华为/三星（需要在真机清单里补测）。
- 连续截图时要不要把「等待发布」并发化（牺牲串行换跟手），等实测排队延迟再定。
