# Tasks

## 1. 图标品牌

- [ ] 1.1 新增 `tool/generate_icons.py`（Pillow）：从 1024 母版生成 Android 五密度 + Web favicon/192/512/maskable；运行脚本并确认所有 PNG 尺寸正确、不再是默认图标
- [ ] 1.2 用生成结果替换 `android/app/src/main/res/mipmap-*/ic_launcher.png` 与 `web/icons/*`、`web/favicon.png`；用例/检查：每个文件可被 Pillow 打开且尺寸符合预期

## 2. 深色模式走查

- [ ] 2.1 清理硬编码亮色：把与主题冲突的 `Colors.white/black87` 改为主题色（黑底看图与彩色图标底除外）；`flutter analyze` 干净
- [ ] 2.2 新增 `test/pages/dark_mode_test.dart`：深色下构建四个 Tab 与记账面板，断言关键文字存在、无异常

## 3. 打包与 CI

- [ ] 3.1 `.github/workflows/ci.yml` 增加 `flutter build apk --debug` 步骤（放在 test 之后、openspec 校验之前）
- [ ] 3.2 新增 `tools/build_release.ps1`：pub get → analyze → test → build apk --release → 打印路径与大小；本地跑一次确认输出

## 4. 性能护栏

- [ ] 4.1 新增 `test/perf/ledger_perf_test.dart`：1 万笔库上跑按月查询 + 关键词搜索，合计 < 10s；本地跑通并记录实测值

## 5. 回归

- [ ] 5.1 `flutter analyze` 干净、`flutter test` 全绿（不低于 237 + 新增）、`flutter build apk --release` 通过
- [ ] 5.2 设备端回归：装上 release APK，确认桌面图标是金豆、暗色模式四个 Tab 可读；结果写入 tasks.md

## Workflow follow-up

- 归档 change：`openspec archive release-polish --yes`
- 归档后回写 `docs/PRODUCT_PLAN.md` §8（M10 状态）与 §14
