# Tasks

> 每个任务完成、验证跑绿后立即原子提交；实现与测试放在同一个提交里。

## 1. 来源应用与待人工处理（数据库）

- [x] 1.1 `transactions` 新增 `sourcePackage`（可空文本）与 `needsReview`（布尔，默认 false），schemaVersion 5 → 6，迁移用 `TableMigration(newColumns:)`
  - 验证：`test/data/db_migration_test.dart` 新增「v5 建库后升级到 v6，旧账仍在、两列为空/false」
- [ ] 1.2 `EntryWriter.submit` 与仓储写入路径支持 `sourcePackage` / `needsReview`，手动记账两列保持默认
  - 验证：`test/services/entry_writer_test.dart` 断言手动记账写入后 `sourcePackage` 为空、`needsReview=false`
- [ ] 1.3 无障碍 / 通知路径入账时写入 `CaptureCandidate.packageName`
  - 验证：`test/services/capture/capture_runtime_test.dart` 断言自动入账行的 `sourcePackage` 等于候选包名
- [ ] 1.4 截图自动入账补 `source: EntrySource.auto`，并在写账前解析当前应用包名写入 `sourcePackage`
  - 验证：单测断言截图入账 `source == auto` 且出现在 `recentAutoEntries()` 结果里
- [ ] 1.5 「最近自动记账」与交易详情显示来源应用（已知包名映射到可读名，未知则显示原包名）
  - 验证：`test/pages/auto_entries_page_test.dart` 断言带来源的行显示应用名，无来源的行不渲染该行

## 2. 排除词只在金额邻域生效

- [ ] 2.1 执行器改为先定位金额行，再只在该行 ±1 行内匹配排除词；通知文本记为单段、行为不变
  - 验证：`test/services/capture/capture_rule_executor_test.dart` 新增「页面别处有券但仍抽出金额」用例
- [ ] 2.2 命中排除词时在运行记录里写明命中的是哪个词、在哪一行
  - 验证：`test/services/capture/capture_runtime_test.dart` 断言 `no_extraction` 事件 `reason` 与 `detail.keyword`

## 3. 金额锚定

- [ ] 3.1 规则生成提示词改为优先输出 `adjacent_label`，并说明「标签必须在页面原文中出现」
  - 验证：`test/services/capture/capture_rule_generator_test.dart` 用假响应断言既有 label 分支仍可解析
- [ ] 3.2 学习器在回放验证前先自检：相邻标签不在页面文本里 → 直接拒绝；regex 策略同页命中多个不同金额 → 拒绝
  - 验证：单测构造「首个 ¥ 是原价、实付在下面」的页面，断言规则被拒且运行记录写明原因

## 4. 通知规则与树不可读

- [ ] 4.1 学习通知规则前先确认通知文本里能查到该笔真值金额；找不到则跳过并记 `learn_skipped(reason=no_matching_notification)`
  - 验证：`test/services/capture/capture_rule_learner_test.dart` 断言无关通知不产出规则
- [ ] 4.2 树不可读判定从「文本为空」放宽为「可读文本 < 40 字符」，命中即标记截图优先并跳过无障碍规则
  - 验证：单测构造 110 节点 / 186 字符的近似支付宝页面，断言被标记且不生成规则

## 5. 抓帧等页面稳定（原生）

- [ ] 5.1 `AccessibilityCaptureService` 取帧改为双帧指纹比对：300ms 取第一帧、再 400ms 取第二帧，一致才上报，最多重试 3 次
  - 验证：`assembleDebug` 通过；真机日志出现「稳定帧」与「重试」两类记录，且同一页面只产生一个指纹
- [ ] 5.2 两次都不一致时采用最后一帧并记一条运行记录说明未稳定
  - 验证：真机在快速滚动页面上触发一次，`events.log` 出现未稳定记录

## 6. 账户待人工处理与渠道映射

- [ ] 6.1 `app_state` 新增 `capture_account_map`（`包名|渠道词 → 账户 id`）的读写
  - 验证：单测覆盖读写、坏数据与未知键
- [ ] 6.2 入账时按「精确同名 → 渠道映射 → 待人工处理」三级决定账户；写 `needsReview`
  - 验证：`test/services/screenshot/auto_entry_test.dart` 断言三级顺序各命中一次
- [ ] 6.3 「最近自动记账」把 `needsReview` 的笔置顶并标注「待处理」，点开可选账户；选定后写映射、清标记、补账户
  - 验证：`test/pages/auto_entries_page_test.dart` 断言待处理置顶、选择后列表刷新且该笔移出待处理

## 7. 门禁与真机回归

- [ ] 7.1 门禁：`flutter analyze` 零告警、`flutter test --exclude-tags screenshots` 全绿、`assembleDebug` / `assembleRelease` 构建成功、`openspec validate --all --strict` 通过
  - 验证：四条命令输出贴进提交说明
- [ ] 7.2 真机回归：同一批页面（支付宝账单详情、淘宝订单详情、京东订单详情、微信账单详情）重跑，规则应能进灰度或给出明确的拒绝原因；账户按渠道映射落位
  - 验证：`adb pull` 的 `events.log` 与诊断页能对每一笔给出结论

## Workflow follow-up

- 归档前回写 `docs/PRODUCT_PLAN.md` 与 `openspec/specs/auto-entry/spec.md`。
