# Spec Delta

## MODIFIED Requirements

### Requirement: 发版 SHALL 有一条命令

打 `v*` 形式的 git tag SHALL 触发发布流水线，在 CI 内完成校验、签名、构建与 Release 发布；维护者 MUST NOT 需要通过手动上传产物来完成一次发版。本机仍 SHALL 保留一条命令出包的能力，供未打 tag 的临时构建使用。

发布版本号 SHALL 由 tag 推导（`v1.2.3` → versionName `1.2.3`），versionCode SHALL 由 `git rev-list --count HEAD` 推导并单调递增；CI 与本机脚本 MUST 使用同一来源，MUST NOT 使用 `github.run_number` 或依赖 `pubspec.yaml` 的手工递增。版本号来源 MUST NOT 要求发版前手工修改 `pubspec.yaml`。

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

#### Scenario: 本机与 CI 的 versionCode 不回退

- **WHEN** 先用本机脚本出包并安装，再安装 CI 为下一个 tag 构建的包
- **THEN** 后者的 versionCode 大于前者，Android 允许覆盖安装
