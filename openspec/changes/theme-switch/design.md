# Design

## 一个控制器，两个消费者

```
ThemeRepository（app_state: theme_mode = system|light|dark）
        ↓ load / set
ThemeController extends ChangeNotifier { ThemeMode mode }
        ├─ BeanApp：ListenableBuilder → MaterialApp.themeMode
        └─ SettingsPage：读 mode 显示、点选项调 set()
```

为什么用 `ChangeNotifier` 而不是把 mode 塞进 Shell 的 setState：`MaterialApp` 在 `ShellPage` **之上**，
主题必须由 App 层的 widget 重建；用控制器可以让设置页（在 App 下层）反过来驱动上层，不用回调层层传递。

## 启动顺序

`main()` 里：
1. 建 `ThemeRepository` 与 `ThemeController`；
2. `await controller.load()` 后再 `runApp`——这样首帧就是正确主题（避免闪一帧亮色）。

读库在 `runApp` 之前会多花几毫秒（打开 sqlite + 一条 select）。对本地库可接受；若以后变慢，再改成"首帧跟随系统 + 读到后切"，
但那会引入一闪，所以现在选简单可靠的方案。

## 存储

`app_state.theme_mode`：`system` / `light` / `dark`。读不到或值非法时按 `system`。
用字符串而不是整数：换版本时人眼可读、迁移不会错位。

## 设置页

```
主题                        跟随系统  ›
   点击 → 底部面板
   ✓ 跟随系统
     浅色
     深色
```

面板用 `BeanSheet`（与规则编辑、账户选择同一个外壳），选中即写库并关闭。

## 关键决策

| 决策 | 选择 | 理由 |
|---|---|---|
| 状态管理 | `ChangeNotifier` 控制器 | 设置页要驱动它上层的 MaterialApp，回调传递太绕 |
| 启动时等待偏好 | 是（runApp 前 load） | 避免"先亮后暗"的闪一帧 |
| 存储格式 | 字符串 | 可读、可迁移 |
| 是否做自动（日落）切换 | 不做 | 三档已经覆盖主要诉求，自动切换反而难预测 |

## 风险

| 风险 | 应对 |
|---|---|
| 读库失败 | 回落到 `system`，不影响使用 |
| 设置页与 App 不同步 | 同一个控制器实例（由 main 注入），不各自读库 |
| 测试里等待 load | `ThemeController` 可注入 `initial`，单测不碰库 |
