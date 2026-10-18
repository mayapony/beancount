# Tasks

## 1. 地基：版本、versionCode、联网

- [x] 1.1 `pubspec.yaml` 增加 `package_info_plus: ^8.3.1` 与 `url_launcher: ^6.3.1`；验证 `flutter pub get` 成功、`flutter analyze` 零告警，且 `flutter pub deps` 中两者为直接依赖
- [x] 1.2 新增 `AppVersion` 值对象与 `loadAppVersion()`（读 `PackageInfo.fromPlatform()`，失败回落 unknown）；验证 `flutter test test/services/update/app_version_test.dart` 覆盖正常值与读取失败
- [x] 1.3 设置页「关于金豆」改为进入 `AboutPage`，页面显示 `v<version>`、GitHub 仓库链接与隐私说明，删除 `v0.0.1` 硬编码；验证 `flutter test test/pages/about_page_test.dart` 断言真实版本且不出现 `v0.0.1`
- [x] 1.4 CI `release.yml` 与本机 `tools/build_release.ps1` 统一用 `git rev-list --count HEAD` 作为 versionCode，删除 `github.run_number`，并同步 `RELEASING.md`；验证 `Select-String` 确认两处无 `run_number`，且 `pwsh -File tools/build_release.ps1 -SkipTests` 构建出的 APK versionCode 等于当前提交数
- [x] 1.5 主清单显式声明 `INTERNET`；验证 `flutter build apk --debug` 成功，合并清单与 `aapt dump permissions` 均包含 `android.permission.INTERNET`

## 2. 更新源、偏好与说明解析

- [x] 2.1 `version_compare.dart`：解析 `v1.2.3`、按数字段比较、忽略 build/预发布后缀与非法输入；验证 `flutter test test/services/update/version_compare_test.dart` 覆盖 `1.0.10 > 1.0.9`、`1.0 == 1.0.0`、`v` 前缀与坏值
- [x] 2.2 `UpdateSource` 与 GitHub 实现：请求头、ETag/304、200 解析 `tag_name` / `body` / `assets` / `digest`，并覆盖 404、403、5xx、畸形 JSON、缺 APK、`SHA256SUMS.txt` 回退；验证 `flutter test test/services/update/github_update_source_test.dart` 全绿（使用 `MockClient`，不发真实网络）
- [x] 2.3 `UpdatePreferences`：`auto` / `last_check` / `etag` / `skipped` / `dismissed` / `pending` 的读写与 24 小时判定；验证 `flutter test test/services/update/update_preferences_test.dart` 用内存 drift 覆盖默认值与往返
- [x] 2.4 `release_notes.dart`：从 release body 提取 `## 变更`，只保留 `feat` / `fix` / `perf` 条目，支持截断与展开；验证 `flutter test test/services/update/release_notes_test.dart` 覆盖正常、无段落、全为 docs/test 三类输入

## 3. APK 下载与校验

- [x] 3.1 `ApkDownloader` 接口与 IO 实现：`http` 流式写 `cache/update/app-release.apk.part`，显示进度，完成后改名；验证 `flutter test test/services/update/apk_downloader_test.dart` 用 `MockClient` 与临时目录断言字节与目标路径
- [x] 3.2 下载取消、超时、HTTP 错误与磁盘错误时删除 `.part` 并回到可重试状态；验证同一测试文件覆盖取消后无残留、超时抛可读错误
- [x] 3.3 SHA-256 校验与地址约束：优先用 asset `digest`，缺失时解析 `SHA256SUMS.txt`；不匹配删除文件；只接受 GitHub releases 下载地址；验证 `flutter test test/services/update/apk_downloader_test.dart` 覆盖匹配、不匹配、无校验和、非法 host 四种情况
- [x] 3.4 下载缓存清理：启动时删除 `cache/update` 下过期/无主 APK，不碰正在下载的 `.part`；验证 `flutter test test/services/update/update_cache_test.dart` 覆盖旧文件删除与新文件保留

## 4. Android 安装桥

- [x] 4.1 主清单增加 `REQUEST_INSTALL_PACKAGES`、受限 `FileProvider`（`${applicationId}.update.fileprovider`，仅 `cache/update`）与 installer `<queries>`，新增 `res/xml/update_file_paths.xml`；验证 `flutter build apk --debug` 成功，合并清单包含权限、provider 与 queries
- [x] 4.2 Kotlin `UpdateInstaller` 与 `MethodChannel("com.jindou.bean_count/update")`：`canInstall`、`openInstallSettings`、`preflight`（versionCode/签名 SHA-256/versionName）、`install`（ACTION_VIEW + MIME）；校验 canonical path 在 `cacheDir/update` 下；验证 `flutter analyze` 与 `flutter build apk --debug` 通过
- [x] 4.3 Dart `ApkInstaller` 接口、MethodChannel 实现与 `FakeApkInstaller`；验证 `flutter test test/services/update/apk_installer_test.dart` 用 mock channel 断言方法名、参数与错误码映射
- [x] 4.4 安装失败类型与文案映射：`permission` / `downgrade` / `signature` / `versionName` / `parse` / `noInstaller`；验证 `flutter test test/services/update/install_failure_test.dart` 覆盖六种 reason，且签名不一致文案包含「先导出」

## 5. 状态机、关于页与更新页

- [x] 5.1 `UpdateController` 状态机：自动/手动检查、24 小时节流、跳过与以后再说、下载/取消/安装、安装返回后重读版本；注入假 source/downloader/installer/clock；验证 `flutter test test/services/update/update_controller_test.dart` 覆盖状态迁移与失败不崩溃
- [x] 5.2 `AboutPage` 接入 controller：自动检查开关、检查更新、上次检查时间、检查中/已是最新/失败原因；验证 `flutter test test/pages/about_page_test.dart` 覆盖开关持久化、手动检查三种结果
- [x] 5.3 更新提示 `BeanSheet` 与 `UpdatePage`：说明折叠、体积/版本、进度/取消/重试、权限提示、预检错误；验证 `flutter test test/pages/update_page_test.dart` 覆盖可更新、下载中、校验失败、签名不一致四种界面
- [x] 5.4 `ShellPage` 首帧后自动检查并弹提示、`update_pending_version` 启动提示、安装返回后重新读版本；验证 `flutter test test/pages/shell_update_test.dart` 覆盖有更新、已跳过、安装成功后提示三种路径
- [x] 5.5 `main.dart` 组装 controller 与 `update_services.dart` 的 conditional import；Web/iOS 返回 null；验证 `flutter build web` 成功，且 Web 产物不含 `dart:io` 相关编译错误

## 6. 文档、联调与真机验收

- [x] 6.1 更新 `docs/PRODUCT_PLAN.md`（把「应用内自更新」移出 Out of Scope、更新 §8/§13）、`README.md`（第一次带更新器的版本需手动安装）、`RELEASING.md`（versionCode 规则、仓库公开、签名一致）；验证 `git diff --check` 通过，三份文档均能检索到对应说明
- [ ] 6.2 增加 `--dart-define=UPDATE_API_BASE` 覆盖点与 `tools/mock_update_feed.ps1`（本地 serve `releases/latest` 形状的 JSON + APK，仅 debug 放行 override host）；验证指向本地 feed 能检查到测试版本，且 release 构建仍只接受 GitHub 域名
- [ ] 6.3 真机端到端：用同一签名构建 `1.0.2/200` 与 `1.0.3/201`，先装 1.0.2，再用本地 feed 完成检查、下载、安装、重启提示；另测未授权未知来源、versionCode 回退、签名不一致三种拦截；验证三类拦截均可复现且不会卸载应用
- [ ] 6.4 全量校验：`flutter analyze`、`flutter test`、`flutter build apk --debug`、`openspec validate --all --strict` 全部通过；验证四条命令均以 0 退出

## Workflow follow-up

- 归档后回写 `docs/PRODUCT_PLAN.md` §8 里程碑状态与 §14 工作队列。
- 发布 v1.0.2 后确认 Release 附件可匿名下载，并在发版说明中提醒这是第一个带应用内更新器的版本、仍需手动安装一次。
