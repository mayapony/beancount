# Proposal

## Why

设置页「主题」那一行写着「跟随系统」，但它是死的：点不动，也没法切到固定亮色或暗色。
白天在户外想把亮度压下来、晚上想固定暗色不让系统切换——这类需求只需要一个三选一，M9 剩下的最后一块里最简单也最常被用到。

## What Changes

- **三档主题**：跟随系统 / 浅色 / 深色，选择立刻生效，重开 App 仍记得。
- **存在本地**：`app_state` 里一个键（`theme_mode`），不新增表、不做迁移。
- **设置页可点**：点「主题」弹三选一，当前项打勾，行尾显示当前值。
- **启动不闪**：App 启动时先读偏好再建 `MaterialApp`（读库期间用跟随系统，读到后切过去），避免"先亮后暗"的跳变。
- 非目标：独立配色主题（多套色板）、按时间自动切换（日落到日出）、字体大小调节。

## Capabilities

### New Capabilities

- `theme-preference`: 主题三档偏好（跟随系统/浅色/深色）的持久化、即时生效与设置页入口

### Modified Capabilities

（无：深色配色本身不变，本次只加"选哪一档"的控制。）

## Impact

- 新增 `lib/data/repositories/theme_repository.dart`（读写 `theme_mode`）
- 新增 `lib/theme/theme_controller.dart`（`ChangeNotifier`，App 与设置页共享）
- `lib/main.dart`：`BeanApp` 变为持有控制器的 StatefulWidget，`themeMode` 跟随它
- `lib/pages/settings_page.dart`：主题行接三选一面板
- `lib/pages/shell.dart`：把控制器传给设置页
- 测试：仓储、控制器、设置面板、App 应用、设备端回归
