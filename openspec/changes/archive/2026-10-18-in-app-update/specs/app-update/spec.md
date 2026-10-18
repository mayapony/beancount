# Spec Delta

## Purpose

让 Android 用户不必手动盯 Releases 页：在 App 内发现新版本、阅读更新说明、下载并安装经过校验的 APK，同时保持本地优先与隐私约束。

## ADDED Requirements

### Requirement: 关于页 SHALL 展示运行时版本

「关于金豆」SHALL 从平台包信息读取 versionName 与 versionCode 并展示（至少包含 `v<version>`）；MUST NOT 使用硬编码版本号。读取失败时 SHALL 显示「版本未知」，且 MUST NOT 影响页面其他内容。

#### Scenario: 展示真实版本

- **WHEN** 安装包 versionName 为 `1.0.1`、versionCode 为 `2`
- **THEN** 关于页显示 `v1.0.1`，不显示 `v0.0.1`

#### Scenario: 包信息不可用

- **WHEN** 平台包信息读取失败
- **THEN** 关于页显示「版本未知」且不崩溃

### Requirement: 自动检查 SHALL 节流且可关闭

Android 上自动检查 SHALL 默认开启，在应用解锁进入主界面后触发，且距上次成功检查不足 24 小时时 MUST NOT 发起网络请求。用户 MUST 能在关于页关闭自动检查；关闭后 MUST NOT 自动发起请求。自动检查失败 MUST NOT 阻塞启动或打断记账。

#### Scenario: 24 小时内不重复请求

- **WHEN** 上次成功检查发生在 12 小时前且用户再次启动 App
- **THEN** 不发起更新请求

#### Scenario: 关闭后不自动请求

- **WHEN** 用户关闭「自动检查更新」后重启 App
- **THEN** 不发起更新请求

#### Scenario: 自动检查失败保持安静

- **WHEN** 启动时网络不可达或 GitHub 返回错误
- **THEN** 不显示错误弹窗，App 正常可用

### Requirement: 手动检查 SHALL 给出明确结果

关于页 SHALL 提供「检查更新」入口；手动检查 MUST 忽略 24 小时节流与「跳过此版本」，并 SHALL 明确显示检查中、已是最新、发现新版本或失败原因之一。检查期间入口 SHALL 禁用，失败后 SHALL 可重试。

#### Scenario: 已是最新

- **WHEN** 当前版本为 `1.0.2` 且最新发布为 `1.0.2`
- **THEN** 显示「已是最新版本」

#### Scenario: 发现新版本

- **WHEN** 当前版本为 `1.0.1` 且最新发布为 `1.0.2`
- **THEN** 打开新版本提示，展示 `1.0.2`

#### Scenario: 检查失败有原因

- **WHEN** 手动检查遇到超时、限流或响应异常
- **THEN** 显示可读原因与重试入口

### Requirement: 更新源 SHALL 是公开的 GitHub Releases

更新检查 SHALL 请求 `https://api.github.com/repos/mayapony/beancount/releases/latest`，只接受非 draft、非 prerelease 的最新发布；对照 SHALL 使用 versionName（忽略前导 `v`）。检查 MUST NOT 要求账号、Token 或私有仓库权限。仓库不可公开访问时 SHALL 以「更新源不可用」失败。

#### Scenario: 最新稳定版更新

- **WHEN** 已安装 `1.0.1`，最新稳定发布 tag 为 `v1.0.2`
- **THEN** 判定有新版本并展示 `1.0.2`

#### Scenario: 同版本不提示

- **WHEN** 已安装 `1.0.2`，最新稳定发布也是 `v1.0.2`
- **THEN** 不提示更新

#### Scenario: 仓库不可访问

- **WHEN** 更新源返回 404 或鉴权错误
- **THEN** 手动检查显示「更新源不可用」，自动检查保持安静

#### Scenario: 预发布被忽略

- **WHEN** 最新发布是 prerelease，而上一个稳定版与当前版本相同
- **THEN** 不提示更新

### Requirement: 更新提示 SHALL 支持延后与跳过

发现新版本时 SHALL 展示版本号、安装包体积与更新说明，并提供「立即更新」「以后再说」「跳过此版本」。选择「以后再说」后 24 小时内 MUST NOT 再自动提示同一版本；选择「跳过此版本」后 MUST NOT 再自动提示该版本，但手动检查 SHALL 仍能看到它。出现更高版本时 SHALL 重新提示。

#### Scenario: 以后再说

- **WHEN** 用户对 `1.0.2` 选择「以后再说」并在 2 小时后重启
- **THEN** 不自动提示 `1.0.2`

#### Scenario: 跳过版本

- **WHEN** 用户对 `1.0.2` 选择「跳过此版本」并重启
- **THEN** 不自动提示 `1.0.2`，手动检查仍显示 `1.0.2`

#### Scenario: 更高版本重新提示

- **WHEN** 用户跳过 `1.0.2` 后出现 `1.0.3`
- **THEN** 自动检查重新提示 `1.0.3`

### Requirement: 下载 SHALL 可观测、可取消并校验完整性

下载 MUST 由用户明确触发；下载中 SHALL 显示进度与已下载体积，并 SHALL 允许取消。完成后 MUST 使用发布元数据中的 SHA-256（asset digest，缺失时用 `SHA256SUMS.txt`）校验；校验失败 MUST 删除文件并拒绝安装。下载失败 SHALL 可重试，取消或失败 MUST NOT 留下可安装的残留文件。

#### Scenario: 下载并校验成功

- **WHEN** 用户点击「立即更新」且下载完成、SHA-256 匹配
- **THEN** 显示「下载完成」并允许安装

#### Scenario: 校验失败

- **WHEN** 下载文件的 SHA-256 与发布元数据不一致
- **THEN** 删除文件并显示校验失败，不提供安装

#### Scenario: 取消下载

- **WHEN** 用户下载到一半点击取消
- **THEN** 停止下载、删除部分文件并回到可重试状态

### Requirement: 安装 SHALL 处理未知来源权限

Android 安装前 SHALL 检查当前应用是否被允许安装未知应用；未允许时 MUST NOT 直接拉起安装器，SHALL 说明原因并提供前往系统设置的入口。用户授权返回后 SHALL 重新检查并允许继续安装。

#### Scenario: 未授权

- **WHEN** 当前应用没有「安装未知应用」权限
- **THEN** 显示说明与「去设置」，不拉起安装器

#### Scenario: 授权后继续

- **WHEN** 用户从系统设置返回且已授权
- **THEN** 安装入口恢复可用

### Requirement: 安装前 SHALL 校验版本与签名

拉起系统安装器前 SHALL 校验 APK 的 versionCode 不小于当前版本、签名证书与当前应用一致、versionName 与发布版本一致。任一不满足时 MUST NOT 拉起安装器，并 SHALL 给出可操作说明。签名不一致时 MUST NOT 自动卸载当前应用或清除数据。

#### Scenario: 版本回退被拦截

- **WHEN** 下载包的 versionCode 小于当前安装版本
- **THEN** 阻止安装并提示版本回退

#### Scenario: 签名不一致被拦截

- **WHEN** 当前安装的是本机调试签名包，下载包是发布签名
- **THEN** 阻止安装，提示先导出数据并说明需要同签名包

#### Scenario: 全部通过

- **WHEN** 权限、versionCode、签名与 versionName 均满足
- **THEN** 拉起系统安装器安装该 APK

### Requirement: 安装完成后 SHALL 反馈并清理

安装前 SHALL 记录待安装版本；应用下次启动且实际版本等于待安装版本时 SHALL 提示「已更新」，并清除记录。未完成安装时 MUST NOT 显示更新成功。已安装或过期的 APK 缓存 SHALL 被清理。

#### Scenario: 更新成功

- **WHEN** 用户安装 `1.0.2` 后重新打开 App，实际版本为 `1.0.2`
- **THEN** 显示「已更新到 1.0.2」并清理安装包

#### Scenario: 安装未完成

- **WHEN** 用户取消系统安装后重新打开 App，实际版本仍为 `1.0.1`
- **THEN** 不显示更新成功

### Requirement: 更新检查 SHALL 最小化数据与网络暴露

更新检查 MUST 只发送 HTTPS GET 与包含版本号的 User-Agent；MUST NOT 携带账本数据、设备唯一标识、账号或 Token。下载 URL MUST 限定为发布元数据中 GitHub 域名的 APK 资源。自动检查 MUST 可关闭。

#### Scenario: 请求不携带账本或设备标识

- **WHEN** 自动或手动检查更新
- **THEN** 请求头与查询参数中只有版本号与标准 HTTP 头，没有账本、设备或账号信息

#### Scenario: 非预期下载地址被拒绝

- **WHEN** 发布元数据给出的 APK 地址不在允许的 GitHub 域名下
- **THEN** 拒绝下载并提示更新源异常

### Requirement: 更新入口 SHALL 仅在 Android 提供

更新检查、下载与安装入口 SHALL 只在 Android 显示；Web 与 iOS MUST NOT 显示更新入口，也 MUST NOT 发起自动检查。iOS 的更新 SHALL 留给 App Store 渠道。

#### Scenario: Web 不显示更新

- **WHEN** 在 Web 构建中打开关于页
- **THEN** 没有检查更新与自动检查入口，且启动时不联网检查

#### Scenario: Android 显示更新

- **WHEN** 在 Android 上打开关于页
- **THEN** 显示真实版本、检查更新与自动检查开关
