# Design

## 图标：一条脚本，一套颜色

`tool/generate_icons.py`（Pillow）画一个「暖砂底 + 金色豆子」的图标：

- 底色 `#FAF7F0`（`BeanColors.surfaceLight` 的砂色系），圆角方形；
- 豆子：金色 `#E8A33D` 的椭圆，倾斜 20°，加一道深金弧线当豆缝，右上角一小片豆绿叶子；
- 所有尺寸由同一张 1024 母版 `resize(LANCZOS)` 得到，避免每次重画导致像素对齐差异。

产出：

| 目标 | 尺寸 |
|---|---|
| Android mdpi/hdpi/xhdpi/xxhdpi/xxxhdpi | 48 / 72 / 96 / 144 / 192 |
| Web favicon | 32 |
| Web Icon-192 / Icon-512 | 192 / 512 |
| Web maskable 192 / 512 | 192 / 512（额外内边距 20%，避免被系统遮罩裁掉） |

不做 Android 8+ 的自适应图标分层（foreground/background XML）：本轮只要"不是默认 F"且不被裁切，留足内边距就够了。

## 深色模式走查清单

按页面过一遍 `Colors.*` 硬编码：

| 位置 | 处理 |
|---|---|
| `attachment_viewer_page`（黑底看图） | 保留：黑底看票据是刻意选择，白字/半透明白在两种主题下都成立 |
| `assets_page` 的账户图标底色 | 保留：白字压在彩色圆上，与主题无关 |
| 其余 `Colors.white/black87` | 改成主题色或 `palette.surface/sand` |
| 设置页的入口图标底色（紫/蓝/青等） | 保留：是图标底色而非文字色 |

验证方式：新增 `test/pages/dark_mode_test.dart`，用 `Brightness.dark` 构建四个 Tab 与记账面板，断言关键文字存在且无异常。
比"肉眼截一张暗色图"可靠，也比 golden 便宜。

## CI：多一步打包

```yaml
- name: 构建 APK（含平台配置校验）
  run: flutter build apk --debug
```

选 `--debug` 而不是 `--release`：debug 构建同样会走 manifest/资源/插件配置，但快得多，CI 主要防"配置被改坏"。

## 发版脚本

`tools/build_release.ps1`：

```powershell
flutter pub get
flutter analyze
flutter test
flutter build apk --release
输出 APK 路径与大小（MB，一位小数）
```

签名：脚本不碰密钥，沿用 `android/key.properties`（不入库）与 Gradle 的默认签名配置；没有签名配置时 Flutter 会用 debug 签名并给出提示。

## 性能护栏

`test/perf/ledger_perf_test.dart`：内存库插入 1 万笔（复用导入路径，比逐条 create 快），然后

- `dayGroups(year, month)` 一次；
- `searchLedger(keyword)` 一次；
- 合计耗时断言 `< 10s`（宽松到只拦数量级退化）。

为什么用宽松上限：CI 机器性能波动大，严格毫秒断言会变成"随机失败"；这个用例的价值是发现"某次改动让查询变成 O(n²)"。

## 关键决策

| 决策 | 选择 | 理由 |
|---|---|---|
| 图标生成方式 | 脚本入仓 | 改色重出，不靠设计师给一堆 PNG |
| 是否做自适应图标 | 不做 | 只需不裁切；分层 XML 收益低 |
| CI 打包 debug | 是 | 验证配置，速度快；release 由发版脚本负责 |
| 性能断言 | 宽松上限 | 防数量级退化，不制造 flaky |
| 暗色验证 | widget 构建 + 关键文字 | 比 golden 便宜且稳定 |

## 风险

| 风险 | 应对 |
|---|---|
| 图标在小尺寸糊 | 母版 1024 下采样；48px 不放叶子细节 |
| 暗色仍有漏网硬编码 | 用例只覆盖关键页；遗漏项记入后续清理 |
| CI 打包拖慢 | 只 build debug；仍比人工发现便宜 |
| 性能用例在慢机器上超时 | 上限 10s，且只在完整 `flutter test` 里跑一次 |
