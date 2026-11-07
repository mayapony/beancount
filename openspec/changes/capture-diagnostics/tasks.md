# Tasks

> 每个任务完成、验证跑绿后立即原子提交；实现与测试放在同一个提交里。
> 真机证据（adb 抓到的 `events.log` 片段）写进对应任务的验证行。

## 1. 事件模型与本地存储（Dart）

- [x] 1.1 新建 `lib/services/capture/capture_diagnostics.dart`：`CaptureDiagKind` 枚举（13 种）+ `CaptureDiagEvent`（`seq` / `at` / `kind` / `package` / `target` / `outcome` / `reason` / `detail` / `evidenceId`）与 `toJson`/`fromJson`
  - 验证：新增 `test/services/capture/capture_diagnostics_test.dart`，覆盖 round-trip、未知 kind 与缺字段不抛异常
- [x] 1.2 `CaptureDiagStore`：`app_state` 前缀 `diag_event:`，环形保留 200 条，按时间升序读出；`clear()` 清空
  - 验证：单测写入 250 条后 `readAll()` 长度为 200，且最旧的 50 条被淘汰
- [x] 1.3 证据环形：`diag_evidence:` 前缀单独保留最近 10 条（页面树文本 / 模型原文），事件用 `evidenceId` 引用
  - 验证：单测写入 12 条证据后只剩最新 10 条，且被淘汰证据对应的事件仍可读（`evidenceId` 悬空时页面显示「证据已淘汰」）
- [x] 1.4 同类合并：同 `kind` + 同 `package` 在 1 秒内重复发生时合并为一条并累加 `count`
  - 验证：单测模拟 5 条 200ms 间隔的 `tree_captured`，只产生 1 条事件且 `count == 5`
- [x] 1.5 JSONL 追加器：写 `<app files>/diag/events.log`，单文件上限 512 KB，超出滚为 `events.log.1`
  - 验证：单测用临时目录写入超过上限，断言产生 `.1` 且新文件从头开始

## 2. 原生侧记录（Kotlin）

- [ ] 2.1 新建 `CaptureDiag.kt`：`SharedPreferences("capture_diag")` 环形保留 100 条 + 复用 `diag/events.log` 追加一行；写失败吞掉不抛
  - 验证：`./gradlew assembleDebug` 通过；真机上开关自动记账后 `adb pull /sdcard/Android/data/com.jindou.bean_count/files/diag/events.log` 能取到文件
- [ ] 2.2 `CaptureRuntime.forward()` 在 `channel == null` 或 `!dartReady` 时记一条 `event_dropped`，说明丢弃原因
  - 验证：真机冷启动后立即触发一次捕获，`events.log` 中出现 `event_dropped`
- [ ] 2.3 `AccessibilityCaptureService` 的 `dumpRunnable` 与 `dumpCurrentTree` 找不到应用窗口时记一条 `window_missing`，含当前活动窗口包名
  - 验证：真机在截图工具栏浮层显示时截图，`events.log` 中出现 `window_missing` 且带 `active=`
- [ ] 2.4 记录服务启动/停止时间戳，`CapturePlugin` 新增 `readDiag` / `clearDiag` / `diagServiceState` 三个通道方法
  - 验证：`./gradlew assembleDebug` 通过；Dart 侧调用 `diagServiceState` 返回最近一次启动时间（在 3 节接线后联调）

## 3. 捕获链路埋点（Dart）

- [x] 3.1 `CaptureRuntime._match` 返回 null 时记 `no_rule` 或 `pending_rule`；`no_rule` 的 detail 带本次页面指纹与规则库中每条规则的包名、目标、档位、指纹
  - 验证：扩展 `test/services/capture/capture_runtime_test.dart`，断言空规则库时产生 `no_rule` 且 detail 含 `fingerprint`
- [x] 3.2 `CaptureRuleExecutor` 提取为空时记 `no_extraction`，detail 带规则标识、抽取策略、是否命中排除词、页面文本前 200 字
  - 验证：单测覆盖「排除词命中」与「正则不中」两条路径各产生一条事件
- [x] 3.3 入账成功记 `entry_written`（金额、方向、来源、分类、账户），写库异常记 `write_failed`
  - 验证：单测断言成功路径 `inserted=true` 时事件金额与实际写入一致
- [x] 3.4 采集开关关闭时记 `gate_closed`（原因 `capture_disabled`），`captureEntry` 通道接线上保证同一事件不重复记录
  - 验证：单测关闭 `capture_enabled` 后调用 `onTreeCaptured`，只产生 1 条 `gate_closed`

## 4. 模型调用埋点

- [ ] 4.1 `VisionReceiptRecognizer` 记 `llm_recognize`：模型原文、解析后字段、被本地丢弃的字段及原因（金额越界、分类/账户不在词表、时间非法）、耗时
  - 验证：扩展 `test/services/ocr/receipt_recognizer_vision_test.dart`，用假响应断言丢弃原因逐条出现
- [ ] 4.2 `CloudCaptureRuleGenerator` 记 `llm_rule_gen`：模型原文、解析出的规则字段；`CaptureRuleLearner` 在验证后补记 `verified` 与最终档位
  - 验证：扩展 `test/services/capture/capture_rule_generator_test.dart` 与 `capture_rule_learner_test.dart`
- [ ] 4.3 `CaptureRuleLearner` 的三种跳过（树为空 / 截图优先 / 云端未配置）各记一条 `learn_skipped`，说明原因
  - 验证：单测分别构造三种条件，断言 `reason` 分别为 `empty_tree` / `screenshot_first` / `unconfigured`

## 5. 诊断页

- [ ] 5.1 新建 `lib/pages/capture_diagnostics_page.dart`：状态卡显示开关、无障碍与通知授权、后台服务是否运行、规则条数与档位分布、距上次捕获/上次入账时间
  - 验证：新增 `test/pages/capture_diagnostics_page_test.dart`，断言零规则时显示「自动记账不会触发」提示、从未入账时显示「从未」
- [ ] 5.2 事件流列表：时间倒序，每条可展开，展开后显示该事件的完整 detail；`no_rule` 额外显示「本次指纹 vs 规则库指纹」对照
  - 验证：widget 测试点开一条 `no_rule`，断言两侧指纹文本都可见
- [ ] 5.3 页面提供「清空记录」并二次确认，清空后合并两源都为空
  - 验证：widget 测试确认后事件列表为空且 store 被调用清空

## 6. 导出与脱敏

- [ ] 6.1 导出报告生成：合并两源事件 + 状态卡快照，默认脱敏——抹商户名、订单号与 6 位以上连续数字，保留金额形态与 8 位指纹
  - 验证：单测输入含商户名、订单号、`¥12.34` 的样本，断言商户与订单号被抹、金额与指纹原样保留
- [ ] 6.2 导出落地：系统分享文本 + 同时写入 `<app files>/diag/export-<时间戳>.txt`
  - 验证：单测断言文件生成且内容与分享文本一致；真机 `adb pull` 能取到该文件

## 7. 接线与验收

- [ ] 7.1 设置 → 自动记账区块新增「诊断记录」入口并接到诊断页；入口复用 `isSupported` 门，iOS / Web 不渲染
  - 验证：扩展 `test/pages/settings_page_test.dart`，断言不支持平台无该入口、Android 支持时点按可打开
- [ ] 7.2 门禁：`flutter analyze` 零告警、`flutter test --exclude-tags screenshots` 全绿、`assembleDebug` / `assembleRelease` 构建成功、`openspec validate --all --strict` 通过
  - 验证：四条命令输出贴进提交说明
- [ ] 7.3 真机排查验收：adb 连着手机，依次在微信、支付宝与一个新 App 上各做一次支付或截图，用诊断页与 `events.log` 解释每一次结果（无规则 / 指纹不匹配 / 提取为空 / 入账）
  - 验证：`adb pull` 出的 `events.log` 片段能对每一笔给出明确结论，并把结论记入下一位修复提案的输入

## Workflow follow-up

- 回写 `docs/PRODUCT_PLAN.md` 的工作队列与本变更的 spec，然后归档。
