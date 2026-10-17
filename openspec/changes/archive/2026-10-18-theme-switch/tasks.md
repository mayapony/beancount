# Tasks

## 1. 存储与控制器

- [x] 1.1 新增 `ThemeRepository`（`app_state.theme_mode = system|light|dark`，非法值回落 system）；`test/data/theme_repository_test.dart` 用例：默认 system、写入后可读、非法值回落
- [x] 1.2 新增 `ThemeController extends ChangeNotifier`：`load()`、`setThemeMode()`（写库 + notify）；用例：set 之后 mode 变、notify 触发一次、写库失败仍生效（内存优先）

## 2. App 与设置

- [x] 2.1 `main.dart`：`ThemeController` 注入 `BeanApp`，`MaterialApp.themeMode` 跟随控制器（`ListenableBuilder`）；用例：控制器改深色后 App 变暗
- [x] 2.2 设置页主题行显示当前档位，点击弹三选一面板，选择后立刻生效并更新行尾；`test/pages/theme_switch_test.dart` 用例：三档文案、选中后文案变化
- [x] 2.3 Shell 把控制器传给设置页；用例：入口页可构建
- [x] 2.4 `flutter analyze` 干净、`flutter test` 全绿（不低于 261 + 新增）

## 3. 回归

- [x] 3.1 设备端回归：设置里切深色 → 界面变暗 → 杀进程重开仍是深色 → 切回跟随系统；结果写入 tasks.md

## 验证记录（2026-10-18）

- `flutter analyze`：No issues found；`flutter test`：**270 通过**（上一轮 261 + 本次 9）
- 设备端 `integration_test/theme_flow_test.dart -d emulator-5554`：通过
  - 设置 → 主题 → 深色：界面立即变暗、行尾显示「深色」
  - 用同一份库重建 App（模拟冷启动、重新 `load()`）：首帧就是深色
- 坑：模拟器系统当时是深色，`ThemeMode.system` 直接渲染成深色 → 用例里先把控制器固定成浅色再断言，避免依赖模拟器状态
- 坑：中途 `pumpWidget(SizedBox.shrink())` 把整棵树卸载会让注入的库被关掉（后续 Shell 初始化报
  `Can't re-open a database after closing it`）；改成直接替换 widget 后正常
## Workflow follow-up

- 归档 change：`openspec archive theme-switch --yes`
- 归档后回写 `docs/PRODUCT_PLAN.md` §8（M9 状态）与 §14
