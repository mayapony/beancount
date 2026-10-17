# Tasks

## 1. 存储与控制器

- [x] 1.1 新增 `ThemeRepository`（`app_state.theme_mode = system|light|dark`，非法值回落 system）；`test/data/theme_repository_test.dart` 用例：默认 system、写入后可读、非法值回落
- [x] 1.2 新增 `ThemeController extends ChangeNotifier`：`load()`、`setThemeMode()`（写库 + notify）；用例：set 之后 mode 变、notify 触发一次、写库失败仍生效（内存优先）

## 2. App 与设置

- [ ] 2.1 `main.dart`：`ThemeController` 注入 `BeanApp`，`MaterialApp.themeMode` 跟随控制器（`ListenableBuilder`）；用例：控制器改深色后 App 变暗
- [ ] 2.2 设置页主题行显示当前档位，点击弹三选一面板，选择后立刻生效并更新行尾；`test/pages/theme_switch_test.dart` 用例：三档文案、选中后文案变化
- [ ] 2.3 Shell 把控制器传给设置页；用例：入口页可构建
- [ ] 2.4 `flutter analyze` 干净、`flutter test` 全绿（不低于 261 + 新增）

## 3. 回归

- [ ] 3.1 设备端回归：设置里切深色 → 界面变暗 → 杀进程重开仍是深色 → 切回跟随系统；结果写入 tasks.md

## Workflow follow-up

- 归档 change：`openspec archive theme-switch --yes`
- 归档后回写 `docs/PRODUCT_PLAN.md` §8（M9 状态）与 §14
