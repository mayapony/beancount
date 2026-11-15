# Design

## Context

现在有两个前台服务，各自 `startForeground` 一条通知：

```
CaptureService    (id 51, channel capture_service)    engine: captureEntry
ScreenshotService (id 41, channel screenshot_service) engine: screenshotEntry
```

两者同属一个进程，各自跑一个 headless FlutterEngine，各有自己的 `AppDatabase` 连接（`NativeDatabase.createInBackground`）。开机恢复由 `ScreenshotBootReceiver` 分别启动；开关分别落在 `CapturePrefs` / `ScreenshotPrefs`。

入账去重分两层：`mergeCandidates()` 负责同一批次内的「包名 + 金额 + 120 秒」合并，数据库侧靠 `dedupeKeyFor()`（秒 + 金额 + 备注）兜底。`_enqueue` 的 flush 定时器是 3 秒，所以停在支付页时每一帧稳定下来都会自己成一批，批与批之间没有共享记忆，数据库去重键又因为秒数不同而全部绕过——这就是同一笔记 4 次的原因。

前台消费侧 `_consumePendingScreenshot()` 是个无节流的 drain 循环：拿一条、弹一个 UI（`error` 走 SnackBar、有 guess 走记账面板）、再拿一条，既不看新鲜度也不合并。

## Goals / Non-Goals

**Goals:**

- 通知栏只留一条常驻通知，文案反映实际开启的通道
- 同一笔支付在页面停留期间只入账一次，且不误伤真实的两笔同额支付
- 前台不再逐条播报过期失败，改成一条可操作的汇总
- 诊断事件能区分「自动记账」与「截屏识别」两条链路

**Non-Goals:**

- 不做「只在支付类 App 截图才识别」的前台应用白名单（漏掉真实支付场景的代价大于收益）
- 不改规则学习 / 验证链路
- 不为省电引入夜间静默或定时停服

## Decisions

### 1. 合并成一个前台服务，两个引擎都留在里面

新增 `CaptureHostService`：`onCreate` 里同时创建 `captureEntry` 与 `screenshotEntry` 两个 FlutterEngine，各自保留原来的 MethodChannel（`/capture`、`/screenshot`），`startForeground` 只调一次。通知文案由两个开关共同决定：

| 自动记账 | 截屏识别 | 常驻通知文案 |
|---|---|---|
| 开 | 开 | 金豆正在守护 · 自动记账 + 截屏监听 |
| 开 | 关 | 金豆正在守护 · 自动记账 |
| 关 | 开 | 金豆正在守护 · 截屏监听 |
| 关 | 关 | 服务停止，无通知 |

- 为什么不复用现有两个服务、只让一个 `startForeground`：另一个服务会退化成普通后台服务，激进省电策略下随时被回收，而截屏监听被回收是静默失效，用户完全看不出来。
- 为什么不是「一个引擎跑两条链路」：两条链路是独立的 Dart entrypoint，各自的初始化、通道与 isolate 生命周期都不同；合成一个入口要把两套运行时塞进一个 isolate，改动面和回归面都更大。
- 通知渠道：保留 `capture_service`（低频、静音）作为唯一常驻渠道，`screenshot_service` 不再使用但也不删除（Android 不允许删除已建渠道，删除会在系统设置里留下幽灵项）。

### 2. 去重改为「跨批次的短期记忆 + 通知不互相合并」

在 `CaptureRuntime` 里维护一个已入账候选的短期记忆（包名 + 金额 + 时间，存活 120 秒），`_write` 成功后写入；`flush` 前先与本批候选一起参与合并判定。

合并规则按来源区分：

- **通知候选**：每条通知各自成笔，不与任何候选合并（通知不会重复推送，重复推送就是真的两笔）。
- **无障碍 / 截图候选**：只与「已存在的候选或 120 秒内的已入账记忆」合并，方向是「后来的并进先前的」，不连锁吞掉第二条通知。

这样「停在支付页反复抓帧」被压成一笔，而「同额两笔真实支付」因为有两条通知而保留两笔。

替代方案：把 `dedupeKeyFor` 的时间精度从秒放宽到分钟——会被否决，因为它同时作用于导入幂等，放宽会让导入把同一分钟内的两笔真账吞掉。

### 3. 前台提示：一条汇总 + 10 分钟时效

`_consumePendingScreenshot()` 改成两步：

1. **先筛**：`createdAt` 超过 10 分钟的条目直接 `take()` 掉丢弃（已入账的不受影响，它们本来就不在队列里），只写一行诊断。
2. **再播报**：本轮剩余条目里，需要用户补救的（`error` 或 `guess` 非空）合并成一条 SnackBar：「有 N 张截图没能自动记账 · 去最近自动记账看看」，点击进列表；不再逐条弹出，也不再自动弹出记账面板。

- 不再自动弹记账面板：截图后立刻打开 App 的场景已经有「识别中 → 已自动记账」通知，事后再弹面板属于重复打扰。
- 为什么保留 SnackBar 而不是完全静默：读取失败（`读取截图失败 · 点击手动记`）是唯一需要用户当场补救的场景，完全静默会让那张图彻底消失。

### 4. 诊断事件带来源字段

`CaptureDiagEvent` 增加 `channel`（`auto` / `screenshot`），落盘为 `channel` 字段；`CaptureDiagKind` 不变。历史记录没有该字段时按类别推断（`llmRecognize` / `llmRuleGen` / `learnSkipped` 归截屏识别，其余归自动记账）。诊断页顶部加三档切换（全部 / 自动记账 / 截屏识别），导出报告里同样按来源分段。

## Risks / Trade-offs

- **服务合并是新进程生命周期**：两个引擎都在同一个 Service 里，任一方 `onDestroy` 抛异常都会连带另一方；需要在 `onDestroy` 里各自 try/catch，并保证 `CaptureRuntime.channel` / `DartReady` 与截图侧 `watcher` 都按原有顺序清理。
- **已安装设备的通知渠道残留**：旧渠道 `screenshot_service` 会留在系统设置里，用户可能以为还能关。缓解：新渠道描述里写清「自动记账与截屏监听共用本通知」。
- **120 秒记忆会让「同额同页两次真实支付」少记一笔**：只要有通知就不会（通知不合并）；只有在通知权限被拒、纯靠无障碍的情况下存在这个风险，此时以「宁可少记一条可补的手动账，也不要四条重复账」为取舍，并在任务里补一条真机验证。
- **10 分钟时效**：用户在别的 App 里截图后立刻切回来仍然能收到汇总提示；超过 10 分钟的图彻底不再提示，只能靠「最近自动记账」核对。这是有意选择的静默边界。
