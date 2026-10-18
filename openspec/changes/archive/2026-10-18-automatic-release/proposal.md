# Proposal

## Why

现在「能出包」但「不能发布」：`tools/build_release.ps1` 只在本机跑，`android/app/build.gradle` 的 release
分支写死 `signingConfig = signingConfigs.debug`，因此所有产物都是 debug 签名、装不上别人的手机；
`pubspec.yaml` 的版本号靠手改，仓库连一个 tag 都没有。发一次版要手动做一堆不可复现的动作。

## What Changes

- **签名接线**：`android/app/build.gradle` 读 `android/key.properties`，有则用 release keystore 签名，
  没有则回退 debug 签名（本地开发不受影响）。密钥文件与 keystore 一律不入库。
- **tag 触发的自动发布**：新增 `.github/workflows/release.yml`，打 `v*` tag（或手动 dispatch）时
  跑 analyze + test → 用 CI 里的 keystore 还原签名 → 出 release APK → **校验不是 debug 签名** →
  按 tag 推导版本号 → 建 GitHub Release 附 APK 与 SHA256。
- **版本号单一来源**：发布时 versionName 取 tag（`v1.2.3` → `1.2.3`），versionCode 取 CI 自增序号，
  不再需要为了发版手改 `pubspec.yaml`。
- **发版手册**：`RELEASING.md` 写清 keystore 生成命令、四个 GitHub Secrets、打 tag 流程与失败排查。
- 非目标：Google Play / App Store 上架、iOS 打包、自建 F-Droid 仓库（ML Kit 为专有依赖，主仓库不可行）、
  AAB 产物、增量更新、tag 与 `pubspec.yaml` 的双向同步脚本。

## Capabilities

### New Capabilities

（无）

### Modified Capabilities

- `release-readiness`：把「发版 SHALL 有一条命令」升级为「发版 SHALL 由 tag 触发并在 CI 完成签名与发布」，
  并新增「发布产物 MUST 用配置的 keystore 签名」与「密钥 MUST NOT 入库/入日志」两条约束。

## Impact

- `android/app/build.gradle`：新增 signingConfigs.release 与 key.properties 读取、debug 回退
- `.gitignore`：新增 `android/key.properties`、`*.jks`、`*.keystore`
- 新增 `.github/workflows/release.yml`、`RELEASING.md`
- `tools/build_release.ps1`：保持本机出包能力，提示文案与签名接线保持一致
- 无新增 Flutter / Gradle 依赖；需要仓库 Secrets：`ANDROID_KEYSTORE_BASE64`、`ANDROID_KEY_ALIAS`、
  `ANDROID_STORE_PASSWORD`、`ANDROID_KEY_PASSWORD`
