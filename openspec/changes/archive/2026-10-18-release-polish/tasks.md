# Tasks

## 1. 图标品牌

- [x] 1.1 新增 `tool/generate_icons.py`（Pillow）：从 1024 母版生成 Android 五密度 + Web favicon/192/512/maskable；运行脚本并确认所有 PNG 尺寸正确、不再是默认图标
- [x] 1.2 用生成结果替换 `android/app/src/main/res/mipmap-*/ic_launcher.png` 与 `web/icons/*`、`web/favicon.png`；用例/检查：每个文件可被 Pillow 打开且尺寸符合预期

## 2. 深色模式走查

- [x] 2.1 清理硬编码亮色：把与主题冲突的 `Colors.white/black87` 改为主题色（黑底看图与彩色图标底除外）；`flutter analyze` 干净
- [x] 2.2 新增 `test/pages/dark_mode_test.dart`：深色下构建四个 Tab 与记账面板，断言关键文字存在、无异常

## 3. 打包与 CI

- [x] 3.1 `.github/workflows/ci.yml` 增加 `flutter build apk --debug` 步骤（放在 test 之后、openspec 校验之前）
- [x] 3.2 新增 `tools/build_release.ps1`：pub get → analyze → test → build apk --release → 打印路径与大小；本地跑一次确认输出

## 4. 性能护栏

- [x] 4.1 新增 `test/perf/ledger_perf_test.dart`：1 万笔库上跑按月查询 + 关键词搜索，合计 < 10s；本地跑通并记录实测值
- [x] 4.2 护栏用例发现的真 bug：搜索先按「最近 2000 笔」截断再匹配，老账搜不到 → 改成 SQL 预筛；补「老账也能搜到」用例

## 5. 回归

- [x] 5.1 `flutter analyze` 干净、`flutter test` 全绿（不低于 237 + 新增）、`flutter build apk --release` 通过
- [x] 5.2 设备端回归：装上 release APK，确认桌面图标是金豆、暗色模式四个 Tab 可读；结果写入 tasks.md

## 验证记录（2026-10-18）

- `flutter analyze`：No issues found；`flutter test`：**241 通过**（上一轮 237 + 本次 4）
- 图标：`tools/../tool/generate_icons.py` 生成 11 个文件；Pillow 复核尺寸全部正确
  （Android 48/72/96/144/192、favicon 32、Web 192/512/maskable 192/512）
- 发版脚本：`pwsh -File tools/build_release.ps1 -SkipTests` → `app-release.apk` **25.5 MB**，SHA256 前 16 位 `6E1E4A4A1350BE63`（未配 key.properties，故为 debug 签名）
- 设备端（emulator-5554，装的是 release APK）：
  - 应用信息页显示新图标（暖砂底 + 金色豆子 + 豆绿叶子）与「金豆」
  - 深色模式（`cmd uimode night yes`）：明细空状态、四个 Tab、设置页全部可读，金色强调不变
- 性能护栏：1 万笔库「按月查询 + 关键词搜索」实测 **24ms**（上限 10s）
- **护栏揪出的真 bug**：`searchLedger` 先 `limit 2000` 再内存匹配，导致老账搜不到（1 万笔库里搜「老账 3」返回 0）
  - 修法：SQL 预筛（备注 LIKE + 分类/子分类/账户/标签 id 命中），精确语义仍在内存里再滤一遍
  - 回归用例：`transaction_search_test.dart` 新增「关键词能搜到超出 limit 的老账」
- 顺手修的诚实性问题：设置页「截图记账」原本写「自动」，实际视觉识别未接入 → 改为「Backlog」
## Workflow follow-up

- 归档 change：`openspec archive release-polish --yes`
- 归档后回写 `docs/PRODUCT_PLAN.md` §8（M10 状态）与 §14
