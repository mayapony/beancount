# Spec Delta

## MODIFIED Requirements

### Requirement: 发版 SHALL 有一条命令

打 `v*` 形式的 git tag SHALL 触发发布流水线，在 CI 内完成校验、签名、构建与 Release 发布；维护者 MUST NOT 需要通过手动上传产物来完成一次发版。本机仍 SHALL 保留一条命令出包的能力，供未打 tag 的临时构建使用。

发布版本号 SHALL 由 tag 推导（`v1.2.3` → versionName `1.2.3`），versionCode SHALL 单调递增；版本号来源 MUST NOT 要求发版前手工修改 `pubspec.yaml`。

#### Scenario: 打 tag 即发布

- **WHEN** 维护者把 `v1.2.3` 推到远端
- **THEN** 流水线跑完 analyze 与 test 后产出 release APK，并创建一个名为 `v1.2.3` 的 GitHub Release，附件含 APK 与校验和

#### Scenario: 一条命令出包

- **WHEN** 维护者在仓库根目录运行发版脚本
- **THEN** 生成 `build/app/outputs/flutter-apk/app-release.apk` 并输出其大小

#### Scenario: 校验不过就不发布

- **WHEN** tag 指向的提交让 `flutter test` 失败
- **THEN** 流水线在构建前失败，不产生 Release

#### Scenario: 版本号来自 tag

- **WHEN** tag 为 `v1.2.3`，`pubspec.yaml` 仍写着 `1.0.0+1`
- **THEN** 产物中的应用版本显示 `1.2.3`，APK 的 versionCode 大于上一次发布

## ADDED Requirements

### Requirement: 发布产物 SHALL 使用配置的 keystore 签名

release 构建 SHALL 在存在签名配置时使用该 keystore 签名，并在缺失配置时回退为 debug 签名以便本地开发；发布流水线 MUST 在发布前校验 APK 的签名证书，若为 `Android Debug` 证书则 MUST 失败，不得发布。

#### Scenario: 配了 keystore 就用它

- **WHEN** `android/key.properties` 指向一个自建 keystore 后执行 release 构建
- **THEN** APK 的签名证书是该 keystore 的证书，不是 `Android Debug`

#### Scenario: 没配也能本地开发

- **WHEN** 仓库里没有 `android/key.properties`
- **THEN** release 构建仍能成功，使用 debug 签名，并给出提示

#### Scenario: 流水线拦住 debug 签名

- **WHEN** 发布流水线里 keystore 未正确还原，构建出的 APK 是 debug 签名
- **THEN** 签名校验步骤失败，Release 不被创建

### Requirement: 签名密钥 SHALL NOT 入库或泄露到日志

keystore 文件与 `android/key.properties` SHALL 被版本控制忽略；CI 中的密钥 SHALL 只通过仓库 Secrets 注入，流水线 MUST NOT 打印密钥内容、密码或 keystore 的可逆编码；缺少 Secrets 时流水线 SHALL 给出指向发版手册的明确错误。

#### Scenario: 密钥不入库

- **WHEN** 在配好发布签名的仓库里执行 `git status`
- **THEN** 看不到 `android/key.properties`、任何 `*.jks` 或 `*.keystore`

#### Scenario: 日志不含密钥

- **WHEN** 发布流水线完整跑完
- **THEN** 日志中不出现 keystore 的 base64 内容与任何密码

#### Scenario: 缺 Secrets 时有明确指引

- **WHEN** 仓库尚未配置签名 Secrets 就打了 tag
- **THEN** 流水线失败信息指向发版手册里需要配置的 Secrets 清单
