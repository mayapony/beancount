# Proposal

## Why

功能面已经基本齐了，但产品还没"像一个产品"：桌面图标还是 Flutter 默认的蓝色 F，深色模式从没系统走过一遍，
CI 只跑 analyze/test（打包能不能过完全靠手动试）。这些都是 M10「发布打磨」的验收项，
也是每次想装到别人手机上时最先被看到的短板。

## What Changes

- **图标品牌**：用一张固定生成的「金豆」图标替换 Flutter 默认图标——Android 五个密度 + Web 的 192/512/遮罩版/favicon，
  生成脚本入仓（`tool/generate_icons.py`），颜色取自现有设计 token，任何人改一行就能重出全套。
- **深色模式走查**：逐屏检查硬编码的亮色（`Colors.white/black87` 等），该跟随主题的改跟随；
  加一个「四个 Tab 在暗色下都能构建、关键文字可读」的回归用例。
- **CI 补齐打包**：在现有 analyze / test / openspec validate 之后加 `flutter build apk --debug`，
  让「平台配置坏了」在 PR 阶段就红，而不是等到手动发版。
- **发版脚本**：`tools/build_release.ps1` 一条命令出 release APK，打印路径与大小（不引入签名配置，签名仍由使用者本地保管）。
- **性能基线**：一条宽松的护栏用例（1 万笔库、按月查询 + 搜索在数秒内完成），只拦灾难性退化，不做脆弱的毫秒断言。
- 非目标：上架商店、iOS 打包流水线、图标自适应前景/背景分层（Android 8+ 会被系统遮罩裁切，本轮图标留足内边距即可）、应用内更新。

## Capabilities

### New Capabilities

- `release-readiness`: 品牌图标、深色模式一致性、可重复的打包与 CI 校验、性能护栏

### Modified Capabilities

（无：不改动任何功能行为。）

## Impact

- `android/app/src/main/res/mipmap-*/ic_launcher.png`、`web/icons/*`、`web/favicon.png`：替换为新图标
- 新增 `tool/generate_icons.py`、`tools/build_release.ps1`
- `.github/workflows/ci.yml`：增加打包步骤
- `lib/**`：暗色模式下硬编码颜色的修正
- 测试：暗色回归用例、性能护栏用例
- 无新增 Flutter 依赖
