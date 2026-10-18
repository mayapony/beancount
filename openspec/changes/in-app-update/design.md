# Design

## Context

见 `proposal.md` 的 Why。这里只列会约束实现的事实：

- 分发只有 GitHub Release。仓库已公开，`releases/latest` 在未鉴权下返回 200，最新稳定版为 `v1.0.1`，附件 `app-release.apk`（47.9 MB）与 `SHA256SUMS.txt`，asset 自带 `digest: sha256:...`。
- App 是 Flutter 3.27.3 / Dart 3.6.1，本地优先，无后端；偏好已有 `app_state(key, value)` 键值表，不需要数据库迁移。
- 设置页「关于金豆」目前写死 `v0.0.1`；`package_info_plus` 未接入。
- versionCode 现在 CI 用 `github.run_number`，本机脚本用提交数（当前 137）；两者混装会版本回退。
- release 清单没有显式 `INTERNET`；现在的权限来自 MLKit 的 `com.google.android.datatransport:transport-backend-cct`。`cloud-receipt-vision` 正在删除 MLKit，删除后 release 会失去联网能力。
- 主清单 `minSdk 23`、`applicationId com.jindou.bean_count`；`MainActivity` 目前只有一行 FlutterActivity。
- Web 构建存在，必须保持可编译；iOS 目录存在，但不走这条更新链路。

## Goals / Non-Goals

**Goals:**

- Android 上完成「发现版本 -> 提示 -> 下载 -> 校验 -> 安装」的闭环，且不依赖自有服务器。
- 版本显示、versionCode、网络权限三处地基一次修好，避免「功能写完但装不上」。
- 更新链路可单测：网络、文件、平台通道都放在接口后面，测试不碰真实网络与安装器。
- 失败可解释、可恢复；签名不一致时绝不自动卸载或清数据。

**Non-Goals:**

- 后台下载、断点续传、静默安装、增量更新、强制更新、beta 频道、回滚到旧版本。
- Web/iOS 自更新；iOS 留给 App Store。
- 在 CI 中跑真实网络或真实安装；端到端安装只在真机手动验证。

## Decisions

### 1. 更新源用 GitHub Releases API，不引入镜像与 Token

`GET https://api.github.com/repos/mayapony/beancount/releases/latest`，请求头：

```
Accept: application/vnd.github+json
X-GitHub-Api-Version: 2022-11-28
User-Agent: BeanCount/<version>
If-None-Match: <etag>        # 有缓存时
```

`releases/latest` 已排除 draft 与 prerelease。响应取 `tag_name`、`body`、`published_at` 与 `assets`；APK 优先按 `app-release.apk` 找，找不到再取第一个 `.apk`。SHA-256 优先用 asset 的 `digest`，缺失时请求 `SHA256SUMS.txt` 解析。

替代方案：

- 静态 `latest.json` + 对象存储：多一套发布与凭据，当前仓库公开后没有必要。
- 公开镜像仓库 + PAT：仓库已公开，不需要。
- App 内置只读 Token：可被反编译提取，且会过期，否决。

约束：仓库 MUST 保持公开；404 映射为「更新源不可用」。未鉴权 60 次/小时，24 小时节流 + ETag 足够。

### 2. 版本读取用 package_info_plus，并锁在兼容版本

新增 `package_info_plus: ^8.3.1`。10.x 要求 Flutter >= 3.38.1 / Dart >= 3.10，当前工具链装不上；8.3.1 要求 Flutter >= 3.19 / Dart >= 3.3，兼容。

`AppVersion` 是纯值对象（`version`、`buildNumber`），由 `PackageInfo.fromPlatform()` 构造；测试注入假值，不依赖平台通道。关于页显示 `v<version>`（需要时附 `(<buildNumber>)`），读取失败显示「版本未知」。

### 3. versionCode 统一为提交数

CI 与 `tools/build_release.ps1` 都使用：

```
git rev-list --count HEAD
```

理由：两条出包链路必须共享同一单调来源。`github.run_number` 只按 Release 工作流计数，数值很小；本机提交数是 137，装过本机包后 CI 的下一版会回退。`pubspec.yaml` 的 `+N` 只服务本地 `flutter run`，不参与发布。

替代方案：tag 转数字（`major*10000+minor*100+patch`）在重发同一版本时无法递增；持久化计数器需要额外文件与冲突处理。提交数在正常 history 下单调，足够个人仓库使用。

CI 已有 `fetch-depth: 0`，`git rev-list --count HEAD` 可用。

### 4. 更新状态放在 App 级 Controller，平台能力放在接口后

```
lib/services/update/
  update_models.dart          AppVersion / UpdateRelease / CheckOutcome / DownloadState / InstallPreflight
  version_compare.dart        纯函数
  github_update_source.dart   UpdateSource 接口 + GitHub 实现（http + ETag + 解析 + 校验和解析）
  update_preferences.dart     app_state 键值（开关/节流/跳过/待安装版本）
  apk_downloader.dart         ApkDownloader 接口（不 import dart:io）
  apk_installer.dart          ApkInstaller 接口 + MethodChannel 实现 + Fake
  update_controller.dart      ChangeNotifier 状态机（不 import dart:io）
  update_services_io.dart     IO 工厂：Android 才创建真实 controller
  update_services_stub.dart   Web 工厂：返回 null
  update_services.dart        conditional export
```

`UpdateController` 由 `main.dart` 创建，注入 `BeanApp -> ShellPage`。它持有当前 `AppVersion`、`UpdateSource`、`UpdatePreferences`、`ApkDownloader`、`ApkInstaller` 与 `DateTime Function()` 时钟，状态通过 `ChangeNotifier` 暴露。

`ShellPage` 只在 controller 非空时、首帧后、解锁后触发自动检查；widget 测试不传 controller，因此不会联网。关于页与更新页接收同一个 controller，下载跨页面继续。

`dart:io` 只出现在 IO 实现与工厂里，Web 构建走 stub；这与现有 `connection_web.dart` 的 conditional import 方式一致。

### 5. 偏好全部存 app_state，不建表

| key | 含义 |
|---|---|
| `update_auto_check` | `'true'` / `'false'`，默认 `'true'` |
| `update_last_check_at` | 上次成功检查的 ISO8601 UTC |
| `update_etag` | 上次 200 响应的 ETag |
| `update_skipped_version` | 用户跳过的版本 |
| `update_dismissed_version` | 用户「以后再说」的版本 |
| `update_dismissed_at` | 「以后再说」的时间 |
| `update_pending_version` | 已拉起安装器、等待重启确认的版本 |

节流只看 `update_last_check_at`；失败不写入，下次启动可重试。`skipped` 是版本级；`dismissed` 是 24 小时级。手动检查忽略两者。

### 6. 下载走 http 流，落到 cache/update 并做双校验

- 目标：`getTemporaryDirectory()/update/app-release.apk`（Android 上是 `cacheDir`），先写 `.part`，成功后再改名。
- 进度：`StreamedResponse.contentLength` + 已收字节；未知长度时显示不确定进度。
- 取消：`CancelToken` 取消订阅、删除 `.part`。
- 超时：连接/首包 15 秒，流空闲 30 秒；超时按失败处理并清理。
- 校验：下载完成后用 `crypto` 对文件做 SHA-256，与发布元数据比对；不一致删除文件并拒绝安装。发布没有提供校验和时同样拒绝安装（fail closed）。
- 下载地址只接受 `https://github.com/mayapony/beancount/releases/download/...`；GitHub 到 `objects.githubusercontent.com` 的跳转由 http 客户端处理。
- 本地联调可用 `--dart-define=UPDATE_API_BASE` 指向 mock feed；只有 debug 构建放行该 override 的 host，release 构建始终只允许 GitHub 域名。
- 体积与磁盘错误映射为可读失败；取消/失败不留可安装文件。

替代方案：`dio` 提供现成进度与取消，但为这一个下载引入新依赖不划算；`http` 已在用。

### 7. 安装自己写 MethodChannel，不引 open_filex

`open_filex` 为符合 Google Play 政策移除了 `REQUEST_INSTALL_PACKAGES`，且其 FileProvider 配置暴露 `root`/`external` 路径；我们只需要安装自己下载的 APK，不应把文件系统暴露面做大。`PackageInstaller` session 能拿到状态，但安装会杀死当前进程，状态回调不可靠，收益有限。

MethodChannel：`com.jindou.bean_count/update`

| 方法 | 返回 | 说明 |
|---|---|---|
| `canInstall` | bool | API 26+ 用 `canRequestPackageInstalls()`；以下返回 true |
| `openInstallSettings` | void | `ACTION_MANAGE_UNKNOWN_APP_SOURCES`，失败回落到应用详情页 |
| `preflight` | map | 解析 APK 的 versionCode / versionName / 签名摘要，与当前包比较 |
| `install` | void | `ACTION_VIEW` + `application/vnd.android.package-archive`，带读权限 |

`preflight` 的返回：`{ok: bool, reason: 'ok'|'parse'|'downgrade'|'signature'|'versionName', apkVersionCode, currentVersionCode, apkVersionName}`；`noInstaller` 由真正的 `install`（带 content URI）判断。

实现要点：

- `PackageManager.getPackageArchiveInfo(path, flags)`；API 28+ 用 `GET_SIGNING_CERTIFICATES`，以下用 `GET_SIGNATURES`。
- 签名比较用证书字节的 SHA-256 集合，不比较可读 DN。
- 版本比较用 `longVersionCode`（API 28+）或 `versionCode`。
- `versionName` 必须等于发布 tag 去掉 `v` 的值；不一致视为发布元数据异常。
- `FileProvider` authority 用 `${applicationId}.update.fileprovider`，paths 只含 `<cache-path name="update" path="update/" />`；Kotlin 侧再校验 canonical path 在 `cacheDir/update` 下。
- 安装 Intent：`ACTION_VIEW`、`setDataAndType`、`FLAG_GRANT_READ_URI_PERMISSION`；`resolveActivity` 为空时返回 `noInstaller`。
- 签名不一致只返回错误，不卸载、不清数据；UI 提示先导出。

### 8. 提示、关于页与更新页

- 设置 →「关于金豆」改为可点，进入 `AboutPage`：真实版本、自动检查开关、检查更新、上次检查时间、GitHub 仓库链接、隐私说明。原有 `v0.0.1` 删除。
- 自动检查发现新版本时，在 `ShellPage` 上弹 `BeanSheet`：版本、体积、更新说明摘要，按钮「立即更新」「以后再说」「跳过此版本」。
- 「立即更新」进入 `UpdatePage` 并开始下载；页面状态：检查中、可更新、下载中（进度/取消）、校验中、可安装、安装中、失败（原因/重试）、已是最新。
- 更新说明从 `body` 的 `## 变更` 段提取；只展示 `feat` / `fix` / `perf` 开头的条目，超过 6 条折叠。没有说明时显示「本次发布没有提供更新说明」。
- 安装完成后进程会被系统杀死；下次启动读取 `update_pending_version`，若等于当前版本则提示「已更新到 x.y.z」，然后清记录与缓存。若不等，不提示成功。
- Web/iOS 不显示入口，也不创建 controller。

### 9. Android 清单与权限

主清单新增：

```xml
<uses-permission android:name="android.permission.INTERNET" />
<uses-permission android:name="android.permission.REQUEST_INSTALL_PACKAGES" />
```

`<application>` 内新增受限 FileProvider；`<queries>` 增加 installer intent，便于 `resolveActivity` 在 Android 11+ 返回结果。

`INTERNET` 不依赖 MLKit 的传递权限；这也是删除 MLKit 后截图识别能继续联网的前提。`REQUEST_INSTALL_PACKAGES` 只用于侧载自更新，不上架 Google Play，文档里写明原因。

### 10. 隐私与安全

- 只发 GET；不发送账本、设备 ID、账号、Token；User-Agent 只含版本号。
- 自动检查默认开启但可关闭；关闭后不发起任何更新请求。
- 只允许 HTTPS；下载 URL 限定 GitHub 域名与 releases 路径。
- SHA-256 校验失败不安装；签名/版本预检不通过不拉起安装器；不自动卸载。
- 不引入遥测；检查失败不记录到远端。

### 11. 失败矩阵

| 场景 | 自动检查 | 手动检查 | 下载/安装 |
|---|---|---|---|
| 离线 / DNS 失败 | 静默 | 「网络不通，检查一下连接」 | 下载失败，可重试 |
| 403 限流 | 静默 | 「检查太频繁，稍后再试」 | 不适用 |
| 404 / 仓库转私有 | 静默 | 「更新源不可用」 | 不适用 |
| 5xx | 静默 | 「GitHub 暂时不可用」 | 下载失败，可重试 |
| 响应畸形 / 缺 APK | 静默 | 「更新信息无法解析」 | 不适用 |
| SHA-256 不匹配 | 不适用 | 不适用 | 删除文件，提示校验失败 |
| 磁盘不足 | 不适用 | 不适用 | 提示存储空间不足 |
| 未授权未知来源 | 不适用 | 不适用 | 提示去设置，不拉起安装器 |
| versionCode 回退 | 不适用 | 不适用 | 阻止安装，提示版本回退 |
| 签名不一致 | 不适用 | 不适用 | 阻止安装，提示先导出 |
| 安装被取消 | 不适用 | 不适用 | 下次启动不提示成功 |

## Risks / Trade-offs

| 风险 | 应对 |
|---|---|
| APK 体积大（v1.0.1 为 47.9 MB；当前 fat APK 约 64 MB），移动网络下载成本高 | 只在用户点「立即更新」后下载，展示发布元数据里的实际体积；不做后台自动下载。删掉 MLKit 后仍未明显变小，后续可评估按 ABI 拆分 |
| GitHub 在国内可能不可达 | 自动检查静默失败；手动检查给原因；保留「打开 Release 页」兜底。更新源地址留 `--dart-define=UPDATE_API_BASE` 覆盖点，便于换镜像或本地联调 |
| 本机 debug 包与发布包签名不同 | 预检拦截并提示先导出数据；不自动卸载。文档明确「日常机只装同签名包」 |
| versionCode 从 run_number 切到提交数，数值跳跃 | 跳跃是向上的，已安装的旧包可升级；首次切换后确认下一次发布 versionCode 大于已装版本 |
| 提交历史被改写导致 versionCode 回退 | 个人仓库正常不合 history；发版前检查 `git rev-list --count` 是否大于上一版 |
| 仓库转私有导致 404 | 发版检查清单加一条「确认仓库公开」；手动检查显示「更新源不可用」 |
| 安装器行为因 ROM 而异 | 用标准 `ACTION_VIEW` + FileProvider；真机覆盖 MIUI/ColorOS 等至少一台验证 |
| 更新说明噪声大 | 客户端过滤 feat/fix/perf 并折叠；后续可在 CI 里生成更短的 notes |
| 下载中 App 被切后台/杀死 | 非目标；重进后重新下载。不做断点续传 |
| 首次带更新器的版本仍需手动装 | README/RELEASING 写明 v1.0.2 的 bootstrap 步骤 |

## Migration Plan

1. 先落「版本显示 + versionCode 统一 + INTERNET」三块地基，确保 release 包能联网、能覆盖升级。
2. 再接检查与提示；此时即使下载/安装未完成，也不会破坏现有使用。
3. 接下载与安装桥；用两台同签名包（v1.0.2、v1.0.3）与本地 mock feed 做端到端验证。
4. 发布 v1.0.2：这是第一个带更新器的版本，用户需手动安装一次；之后 v1.0.3+ 可在 App 内更新。
5. 回滚策略：不发低 versionCode 的包；有问题就发更高的修复版。已下载但未安装的缓存在启动时清理。

## Open Questions

无。自动检查默认值、提示节奏、签名不一致策略已在 spec 与本文中定下；后续若要加 beta 频道或强制更新，另开 change。
