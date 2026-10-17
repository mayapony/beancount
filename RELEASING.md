# 发版手册

两条路：**自动发布**（打 tag，CI 出包并发 GitHub Release）与**本机出包**（不发布，只拿个 APK）。

发布渠道目前只有 **GitHub Release**。Google Play / App Store 上架与自建 F-Droid 仓库见文末「暂不支持」。

---

## 一、一次性准备：生成签名密钥

发布用的 keystore 只生成一次，之后**永不变更**——换了它，老用户无法覆盖升级（Android 会报签名冲突）。
生成后立刻备份到密码管理器或离线介质；仓库里只放「怎么用」，不放密钥本身。

```powershell
# 在 android/ 目录下执行（-dname 可改成你自己的信息）
keytool -genkeypair -v `
  -keystore release-keystore.jks `
  -storetype JKS `
  -keyalg RSA -keysize 2048 -validity 10000 `
  -alias jindou `
  -dname "CN=Bean Count, OU=Personal, O=BeanCount, L=Shanghai, ST=Shanghai, C=CN"
# 会提示输入 keystore 密码与 key 密码（可以直接用同一个）
```

> 有效期建议 ≥ 10000 天：Google Play 要求密钥至少用到 2033 年；自建分发同样别让它过期。

产物：`android/release-keystore.jks`。它已被 `.gitignore` 忽略（`*.jks`），`git status` 里不该出现。

### 配置 GitHub Secrets

仓库 → Settings → Secrets and variables → Actions → New repository secret，加四个：

| Secret | 值 |
|---|---|
| `ANDROID_KEYSTORE_BASE64` | keystore 的 base64 单行文本（见下） |
| `ANDROID_KEY_ALIAS` | `jindou` |
| `ANDROID_STORE_PASSWORD` | keystore 密码 |
| `ANDROID_KEY_PASSWORD` | key 密码（与上一项相同就填同一个） |

生成 base64（Windows PowerShell，**注意不要带换行**）：

```powershell
[Convert]::ToBase64String([IO.File]::ReadAllBytes("android/release-keystore.jks")) | Set-Clipboard
```

macOS / Linux：

```bash
base64 -w0 android/release-keystore.jks   # macOS 用 base64 -i，不加 -w0
```

> 这四个值是**唯一**的密钥来源。别把它们写进仓库、脚本、Issue、聊天记录或 CI 日志。

---

## 二、发一次版

```powershell
# 1. 版本号：v1.2.3 → versionName 1.2.3，versionCode 由 CI 自增（无需改 pubspec.yaml）
# 2. 打 tag 并推上去
git tag v1.0.1
git push origin v1.0.1
```

推上去之后 `.github/workflows/release.yml` 会依次做：

1. `flutter pub get` → `flutter analyze` → `flutter test`（**任何一步红就不发布**）
2. 从 Secrets 还原 keystore，写 `android/key.properties`（不打印内容）
3. `flutter build apk --release --build-name=<tag 去掉 v> --build-number=<run_number>`
4. `apksigner verify --print-certs`，证书里含 `Android Debug` 就失败
5. 生成 `SHA256SUMS.txt`，创建 GitHub Release（附 APK + 校验和，notes 自动列出上次 tag 以来的提交）

跑完在 Releases 页就能下载。安装：`app-release.apk` 直接侧载（Android 6.0+）。

### 演练（不发版）

Actions → Release → Run workflow（手动 dispatch）。会完整跑校验、签名、构建与签名检查，
产物留在这次 run 的 Artifacts 里，**不会**创建 Release。适合第一次配完 Secrets 时验证。

### 想先看 changelog？

Release notes 由 `git log --no-merges --pretty='- %s' <上一个tag>..<这次tag>` 生成，
提交信息本来就是 `<type>(<scope>): 中文描述`，所以 notes 直接可读。要手写就在 GitHub 上编辑该 Release。

---

## 三、本机出包（不发布）

```powershell
pwsh -File tools/build_release.ps1              # 完整校验 + 出包
pwsh -File tools/build_release.ps1 -SkipTests   # 只出包（赶时间用）
```

- 有 `android/key.properties` → 用发布签名（和 CI 同签名，可直接覆盖安装）。
- 没有 → 回退 debug 签名，能装能跑，但**不要**发给别人。

本机 `key.properties` 长这样（相对 `android/app/` 解析）：

```properties
storeFile=../release-keystore.jks
storePassword=你的密码
keyAlias=jindou
keyPassword=你的密码
```

缺字段时 Gradle 会直接报「缺少字段」，不会静默打成 debug 包。

---

## 四、排障

| 现象 | 原因 / 处理 |
|---|---|
| `缺少签名 Secrets：ANDROID_...` | Secrets 没配全，按上表补齐；错误信息里会列出缺哪几个 |
| `APK 是 debug 签名，不能发布` | keystore 没还原成功（base64 带换行最常见），或别名/密码不对 |
| `android/key.properties 缺少字段` | 本机 `key.properties` 少写一行；四项都必须有 |
| 覆盖安装报「签名不一致」 | 现有 APK 是 debug 签名或另一把 keystore 签的；先卸载，或用同一把密钥 |
| tag 推上去了但没跑 | 确认 tag 是 `v` 开头（`v1.0.1`，不是 `1.0.1`） |
| Release 建了但附件缺失 | 构建步骤失败；看 run 日志里的 `构建 release APK` 步骤 |

---

## 五、暂不支持（以及为什么）

| 渠道 | 现状 | 原因 |
|---|---|---|
| Google Play | ❌ 未接 | 需要 Play Console 账号、AAB 产物、服务账号 JSON；新账号还有「20 人测试 14 天」门槛。要接时复用同一把 keystore 即可 |
| F-Droid **主仓库** | ❌ 不可行 | ①`com.google.mlkit:text-recognition-chinese` 是 Google 专有依赖，属 F-Droid 拒绝的 NonFreeDep；②F-Droid 用**自己的**密钥签名并自行构建，我们的签名用不上；③仓库当前无 LICENSE 文件。 |
| F-Droid **自建仓库** | 🟡 可做，未做 | 用自己的签名 + `fdroid` CLI 生成 `index-v2`，托管到 GitHub Pages，用户添加仓库地址即可在 F-Droid 客户端里自动更新。需要额外一个 change（签名复用本文档的 keystore） |
| iOS / App Store | ❌ 未接 | 需要 macOS runner 与 Apple 开发者账号（$99/年） |
