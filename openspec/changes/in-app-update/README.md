# in-app-update

应用内检查更新、下载 APK 并拉起系统安装器

## 真机验收（2026-10-18，Android 16 模拟器 beecount_api36）

联调方式：`adb reverse tcp:8787 tcp:8787` + `--dart-define=UPDATE_API_BASE=http://127.0.0.1:8787`，
mock feed 由 `tools/mock_update_feed.ps1` 提供。

- **成功路径**：v1.0.2（versionCode 200，debug 签名）→ v1.0.3（201，同一签名）；检查、下载 78 MB、系统安装器确认、版本更新成功，重启提示「已更新到 v1.0.3」。
- **未授权未知来源**：首次安装前显示「需要允许金豆安装未知应用」+「去设置」，未拉起安装器；授权后重试可继续。
- **versionCode 回退**：feed 提供 v1.0.4（199），预检拦截并提示「安装包版本低于当前版本」，版本仍为 1.0.3。
- **签名不一致**：feed 提供 release 签名 v1.0.5（205），预检拦截并提示「请先导出数据备份」，应用未被卸载，版本仍为 1.0.3。
