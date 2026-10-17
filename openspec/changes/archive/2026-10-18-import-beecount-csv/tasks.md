# Tasks

## 1. 依赖与解析器

- [x] 1.1 在 `pubspec.yaml` 加入 `csv`、`archive` 与 `file_picker`，`flutter pub get` 后确认 `flutter analyze` 通过
- [x] 1.2 实现 `lib/services/import/bee_count_csv.dart`：去 BOM、表头别名映射、缺列报错；用 `test/fixtures/beecount_sample.csv` 单测验证中文表头可解析、英文表头可解析、缺列返回错误
- [x] 1.3 实现行解析：金额字符串 → 整数分、时间 trim 后解析、类型映射（收入/Income→income、支出/Expense→expense、转账→跳过）；单测覆盖 `38.5→3850`、`0.10+0.20` 不产生浮点误差、非法时间被标记为非致命错误
- [x] 1.4 标签与附件列拆分：标签按逗号拆、去空；附件列拆成文件名列表（不再拼进备注）；单测覆盖 `报销,出差`、空值、`图片记账,AI记账`
- [x] 1.5 实现 `lib/services/import/bee_count_archive.dart`：`ZipDecoder` 取 `beecount_*.csv`、`GZipDecoder`+`TarDecoder` 取 `images/<fileName>`，读 `metadata.json` 补 `originalName`/`fileSize`；单测用自造的小 zip 覆盖"有附件包 / 只有 csv / 包内缺图 / 非法文件名 `../x.jpg`"

## 2. 映射与导入计划

- [x] 2.1 实现 `buildImportPlan(parsed, existing)`：分类 `(名称,类型,父名称)` 缓存去重、账户/标签集合去重、文件内 `dedupeKey` 去重、按原因分类统计；单测验证 50 行同分类只计划 1 个分类、重复行进 skipped
- [x] 2.2 复用 `add-local-storage` 的仓储实现 `applyPlan(plan)`：分块事务（200 行/块）、先建分类/账户/标签、`INSERT OR IGNORE` 写入交易；单测验证同一计划执行两次第二次新增为 0
- [x] 2.3 生成 `ImportReport`（成功/跳过/失败，失败含行号与原因，附件张数与缺失数），并支持导出为文本；单测断言报告字段与计数与输入一致
- [x] 2.4 附件写入：`applyPlan` 在交易落库后调用 `AttachmentRepository.addAttachment`，同名文件只写一次、多笔共享；单测验证"两行同一文件只落盘一次""缺图只记 warning 不失败""导入回滚后孤儿文件被清理"

## 3. 导入界面

- [x] 3.1 设置页新增「数据管理」分组与「从 BeeCount 导入」入口，点击进入导入页；widget test 验证入口存在且可导航
- [x] 3.2 导入页：选择文件（`zip`/`csv`）→ 解析 → 预览（可导入条数、将新建的分类/账户/标签、跳过原因摘要、图片张数与体积）→ 取消返回不写库；widget test 用 fixture 验证预览数字正确
- [x] 3.3 确认导入：显示进度、失败不中断、完成后展示报告页（含"复制报告"）；widget test 验证导入 3 行后明细页出现这 3 笔

## 4. 真实数据与回归

- [x] 4.1 用用户真实备份跑一遍解析与 `buildImportPlan`：真实文件放 `test/fixtures/local/`（**该目录已 gitignore，真实账本数据不进 git**），核对总行数 = 可导入 + 跳过、附件张数与包内一致；git 里只保留 `test/fixtures/beecount_sample*.csv` 这类脱敏样本
- [x] 4.2 端到端：Android 模拟器上 `integration_test/import_flow_test.dart` 用脱敏 zip 走完「预览 → 导入 → 报告」，并断言图片真的落到应用目录、交易真的进库；真实 zip 的解析/计划在 4.1 用本地数据验证（真实备份不进 git，设备上手动选文件留待你自己点一次）
- [x] 4.3 1 万行 fixture 性能验证：导入 < 3s（Debug 可放宽到 8s），内存无异常增长
- [x] 4.4 在 `docs/` 补一页「从 BeeCount 迁移」说明（导出位置、导入步骤、跳过原因释义）

## 5. 集成检查

- [x] 5.1 `flutter analyze` 零告警、`flutter test` 全绿（新增解析/计划/报告单测与导入 widget test）
- [x] 5.2 Web 下入口可见，导入页顶部提示「Web 只用于预览」，并禁用选择文件按钮（浏览器沙盒没有文件目录，图片无法落盘）

## Workflow follow-up

- 依赖的 `add-local-storage` 需先归档，再实施本变更。
- 实现完成后按项目评审要求归档该 change（`openspec archive import-beecount-csv`）。
