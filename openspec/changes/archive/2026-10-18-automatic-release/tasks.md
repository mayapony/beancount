# Tasks

## 1. 签名接线

- [x] 1.1 `android/app/build.gradle` 读取 `android/key.properties`（`storeFile`/`storePassword`/`keyAlias`/`keyPassword`），存在则 `signingConfigs.release` 生效，不存在则回退 `signingConfigs.debug`；`flutter build apk --release` 在两种情况下都能出包
- [x] 1.2 `.gitignore` 增加 `android/key.properties`、`*.jks`、`*.keystore`，并在 `RELEASING.md` 写明密钥绝不入库
- [x] 1.3 用一次性 keystore 本地验证：配了 key.properties 时 `apksigner verify --print-certs` 显示自建证书、未配时显示 `Android Debug`（验证完删掉临时密钥）

## 2. tag 触发的自动发布

- [x] 2.1 新增 `.github/workflows/release.yml`：触发条件 `push tags: v*` 与 `workflow_dispatch`；`permissions: contents: write`
- [x] 2.2 流水线步骤：checkout → flutter 3.27.3 → `pub get` → `analyze` → `test` → 从 `ANDROID_KEYSTORE_BASE64` 还原 keystore 并写 `android/key.properties`（密码走 Secrets，不回显）
- [x] 2.3 按 tag 推导版本：`v1.2.3` → `--build-name=1.2.3`，`--build-number=${{ github.run_number }}`；无 tag 的 dispatch 用 `pubspec.yaml` 的版本
- [x] 2.4 发布前护栏：`apksigner verify --print-certs` 检查 APK 签名，若证书含 `Android Debug` 则失败；计算 SHA256 并写入 Release 说明
- [x] 2.5 建 GitHub Release（附 APK + `SHA256SUMS.txt`），release notes 指向同一 tag 的提交区间
- [x] 2.6 无 Secrets 时（fork / 首次配置前）工作流给出明确失败信息，指向 `RELEASING.md`，而不是晦涩的 Gradle 报错
- [x] 2.7 首次真实发版验证：配好四个 Secrets 后打一个测试 tag，确认 Release 附件可下载、签名证书不是 `Android Debug`

## 3. 文档与本机一致性

- [x] 3.1 新增 `RELEASING.md`：keystore 生成命令、四个 Secrets、打 tag 发版流程、失败排查、签名变更注意事项
- [x] 3.2 `tools/build_release.ps1` 提示文案与签名接线一致（有 key.properties 时说明用的是发布签名；版本号默认取最近 tag 与提交数）

## 4. 回归

- [x] 4.1 `flutter analyze` 干净、`flutter test` 全绿、`openspec validate automatic-release --strict` 通过
- [x] 4.2 `flutter build apk --release` 通过（无 key.properties，走 debug 回退），确认改动没有破坏日常构建

## 验证记录（本地，未推送到 GitHub）

- `flutter analyze`：No issues found；`flutter test`：**320 通过**；`openspec validate automatic-release --strict`：valid
- 无 `android/key.properties`：`flutter build apk --release --build-name=0.0.1-test --build-number=1` → 45.7 MB，`apksigner` 显示 `CN=Android Debug`（回退生效）
- 临时 keystore（别名 `testrelease`）：同一命令 → `apksigner` 显示 `CN=Bean Count Release Test`（签名接线生效），`aapt2 dump badging` 显示 `versionCode='2' versionName='0.0.2-test'`（tag 推导版本生效）
- 字段缺失护栏：只写 `storeFile`/`storePassword` 的 key.properties → Gradle 直接失败并报「缺少字段：keyAlias, keyPassword；写法见 RELEASING.md」
- 临时 keystore 与 key.properties 已删除；`git status` 看不到密钥（`android/.gitignore` 亦已覆盖 `key.properties`/`*.jks`/`*.keystore`）
- workflow YAML 已解析校验（13 个步骤）
- 真实发版（2.7）：`v1.0.1` tag 推送后由 GitHub Actions 完成签名与发布，Release 附件可下载、安装正常；本机无 `gh`、仓库为私有，GitHub 侧结果由仓库所有者确认

## Workflow follow-up

- 归档 change：`openspec archive automatic-release --yes`
- 归档后回写 `docs/PRODUCT_PLAN.md` §8（M10 状态）与 §13（发版方式）
