# Tasks

## 1. PIN 摘要与仓储

- [ ] 1.1 新增 `pinHasher.hash(pin, {salt, iterations})` 与 `verify(pin, salt, digest)`：随机盐、SHA-256 迭代 10000 次、常量时间比较；`test/services/pin_hasher_test.dart` 覆盖「同一 PIN 不同盐摘要不同」「正确/错误校验」「长度校验」
- [ ] 1.2 新增 `LockRepository`（`app_state` 存 `lock_enabled / lock_pin_salt / lock_pin_digest / lock_pin_length`）：`isEnabled / setPin / verify / disable`；用例：设置后可校验、关闭后不可校验、库里没有明文 PIN

## 2. 锁定页

- [ ] 2.1 `LockScreen`：圆点、数字键盘（复用记账键盘视觉）、错误提示与抖动；`test/pages/lock_screen_test.dart` 用例：输对解锁回调、输错提示且不清空位数
- [ ] 2.2 连续 5 次失败后限速 30 秒并显示倒计时；用例：用可注入时钟验证锁定期间不接受输入、超时后恢复
- [ ] 2.3 正确解锁后错误计数归零；用例一条

## 3. 入口与生命周期

- [ ] 3.1 `LockGate`：读锁状态决定显示 `LockScreen` 还是 `ShellPage`；未开启直接进入、读库失败按未开启处理；`test/widgets/lock_gate_test.dart` 两条用例
- [ ] 3.2 后台超过 60 秒回来重新锁定、10 秒回来不打扰；用例：直接调 `didChangeAppLifecycleState` + 注入时钟
- [ ] 3.3 `main.dart` 用 `LockGate` 包住 `ShellPage`；用例：构建不崩

## 4. 设置流程

- [ ] 4.1 设置页「应用锁」从 `M9` 占位改为真实入口，显示当前状态；用例：入口可点、状态文案正确
- [ ] 4.2 `AppLockPage`：开启（两次输入一致）、修改（先验证旧 PIN）、关闭（先验证旧 PIN）；用例覆盖三条主路径与「两次不一致」错误提示

## 5. 回归

- [ ] 5.1 `flutter analyze` 干净、`flutter test` 全绿（不低于 211 + 新增）
- [ ] 5.2 设备端回归：设置 PIN → 冷启动出现锁屏 → 错误 PIN 被拒 → 正确 PIN 进入 → 关闭后不再拦截；结果写入 tasks.md

## Workflow follow-up

- 归档 change：`openspec archive app-lock --yes`
- 归档后回写 `docs/PRODUCT_PLAN.md` §8（M9 状态）与 §14，并把「生物识别」写进 Backlog
