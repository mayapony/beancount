# release-readiness Specification

## Purpose
让产品具备"可以装到别人手机上"的最小成品度：统一的品牌图标、在深色模式下没有看不清的文字、一条命令能出包、CI 能拦住打包失败，以及一条只拦灾难性退化的性能护栏。

## Requirements

### Requirement: 应用 SHALL 使用品牌图标

Android 的五个密度与 Web 的 192/512/遮罩图标、favicon SHALL 使用同一套「金豆」图案；图标 SHALL 由脚本从设计 token 的颜色生成，脚本 MUST 能从零重出全部尺寸。

#### Scenario: 图标不是 Flutter 默认

- **WHEN** 用户把 App 装到桌面
- **THEN** 图标是金豆图案（暖砂底 + 金色豆子），不是 Flutter 的蓝色 F

#### Scenario: 脚本可重出

- **WHEN** 有人改了图标配色并重新运行生成脚本
- **THEN** 五个密度与 Web 图标全部更新为同一套图案

### Requirement: 界面 SHALL 在深色模式下可读

四个 Tab、记账面板、详情页与设置各子页 SHALL 在深色模式下使用主题色，MUST NOT 出现"深色背景上的固定深色文字"或"深色背景上的白色硬编码块"；必要的固定色（如查看大图的黑底）SHALL 只用于明确的中性场景。

#### Scenario: 四个 Tab 暗色可构建

- **WHEN** 以深色主题构建 Shell 并切换四个 Tab
- **THEN** 没有构建异常，关键文字（Tab 名称、页面标题）存在

#### Scenario: 记账面板暗色可读

- **WHEN** 深色模式下打开记一笔面板
- **THEN** 金额、分类名、备注行都使用主题文字色，不出现黑字黑底

### Requirement: CI SHALL 校验可打包

持续集成 SHALL 在 analyze、test、openspec validate 之后执行一次 APK 构建；构建失败 SHALL 使该次检查失败。

#### Scenario: 平台配置坏了会红

- **WHEN** 有人改坏了 Android 清单或依赖配置
- **THEN** CI 的打包步骤失败，合并被拦下

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

### Requirement: 性能 SHALL 有护栏

系统 SHALL 提供一条性能护栏用例：在 1 万笔交易的库上执行「按月查询 + 关键词搜索」，耗时 MUST 低于一个宽松上限；用例只用于拦截数量级退化。

#### Scenario: 万笔库仍可查询

- **WHEN** 库中有 1 万笔交易，执行一次按月查询与一次关键词搜索
- **THEN** 两者合计在数秒内完成，用例通过

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
