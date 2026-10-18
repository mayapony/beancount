# Proposal

## Why

金豆目前只通过 GitHub Release 分发 Android APK（打 tag 由 CI 出包），用户升级只能自己盯 Releases 页手动下载。仓库转公开后，`releases/latest` 已经是现成的公开更新源，但 App 里没有任何版本发现、下载或安装能力；设置页「关于金豆」还写死 `v0.0.1`，而实际版本是 `1.0.1+2`。

同时，现有发版链路的 versionCode 来源不一致：CI 用 `github.run_number`（很小），本机脚本用提交数（当前 137）。装过本机包后再装 CI 包会触发 `INSTALL_FAILED_VERSION_DOWNGRADE`；这正是应用内安装必须先修的地基。release 包也没有显式 INTERNET 权限（现在靠 MLKit 的 `datatransport` 带入，删掉 MLKit 后会断网）。

## What Changes

- 新增应用内更新：设置 →「关于金豆」展示真实版本；自动或手动检查 GitHub Releases 最新稳定版；发现新版本后展示版本、体积与更新说明。
- 新增 Android 下载与安装：应用内下载 APK 到缓存、显示进度与取消、校验 SHA-256；安装前检查未知来源权限、versionCode 不降级、签名与 versionName 一致，再拉起系统安装器。
- 安装包与权限：主清单显式声明 `INTERNET`、`REQUEST_INSTALL_PACKAGES`；新增受限 FileProvider（只暴露 `cache/update`）。
- 修复版本号：CI 与本机脚本统一用 `git rev-list --count HEAD` 作为 versionCode；「关于」版本从 `package_info_plus` 读取，不再硬编码。
- 更新源：`https://api.github.com/repos/mayapony/beancount/releases/latest`；24 小时节流 + ETag；自动检查失败静默，手动检查给出可读原因。
- 安全与隐私：只发送 GET 与带版本号的 User-Agent，不上传账本数据、设备标识或安装 ID；自动检查可关闭；签名不一致时 MUST NOT 自动卸载，提示先导出数据。
- 文档：`PRODUCT_PLAN.md` 把「应用内自更新」从 Out of Scope 移出；`RELEASING.md` 补充 versionCode 规则与「第一个带更新器的版本仍需手动装一次」。
- 非目标：后台下载与断点续传、静默安装、强制更新、增量更新、iOS 自更新、beta 频道。

## Capabilities

### New Capabilities

- `app-update`: 版本发现、更新提示、APK 下载校验与 Android 安装前置检查；包含更新源、节流、隐私与平台范围。

### Modified Capabilities

- `release-readiness`: versionCode 的推导来源与跨 CI/本机单调性。

## Impact

- 新代码：`lib/services/update/`（版本比较、GitHub 源、偏好、下载、安装桥、控制器）、`lib/pages/about_page.dart`、`lib/pages/update_page.dart`、更新提示 sheet。
- 修改：`lib/main.dart`、`lib/pages/shell.dart`、`lib/pages/settings_page.dart`、`pubspec.yaml`、Android 清单与 Kotlin 桥、`.github/workflows/release.yml`、`tools/build_release.ps1`、`RELEASING.md`、`README.md`、`docs/PRODUCT_PLAN.md`。
- 依赖：新增 `package_info_plus ^8.3.1`、`url_launcher ^6.3.1`（10.x / 6.3.3 要求更高的 Flutter/Dart，不兼容当前 3.27.3 / 3.6.1）；复用 `http`、`path_provider`、`crypto`。
- 兼容性：仅 Android 提供更新入口，Web/iOS 隐藏；无数据库迁移（偏好存 `app_state`）。
- 运维：仓库 MUST 保持公开；第一个带更新器的版本（v1.0.2）仍需手动安装一次。
