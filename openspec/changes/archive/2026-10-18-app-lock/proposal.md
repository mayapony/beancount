# Proposal

## Why

金豆里现在有真实的收支、账户余额和票据照片，但谁拿起手机都能直接打开。「本地优先、无账号」的产品在隐私上还缺最后一道门：
M9 的「应用锁」是唯一一个**不加就等于默认公开**的能力。

## What Changes

- **PIN 锁**：设置 4–6 位数字 PIN；开启后每次冷启动（以及离开超过 1 分钟回来）都需要输入 PIN 才能进入。
- **PIN 安全存储**：不存明文。随机盐 + `SHA-256` 迭代 1 万次后保存摘要，校验时同样计算再比较；`app_state` 表里看不到可用的 PIN。
- **设置页入口**：设置 →「应用锁」：开启（两次输入一致才生效）、修改 PIN（需先验证旧 PIN）、关闭（需验证当前 PIN）。
- **锁定页**：6 位圆点 + 自定义数字键盘（与记账键盘同一套视觉），错误抖动 + 提示，连续错 5 次后 30 秒内不再接受输入。
- 非目标：**生物识别**（`local_auth` + Android 平台配置，单独一轮做，见 Backlog）、图案锁、修改后强制退出（应用锁不涉及数据加密）、忘记 PIN 的找回（本地无账号，只提示"重装会丢数据"）。

## Capabilities

### New Capabilities

- `app-lock`: PIN 锁的开关、设置/修改/关闭、解锁流程与失败限速

### Modified Capabilities

（无：数据存储与其它功能不变，锁只在入口处拦截。）

## Impact

- 新增 `lib/services/security/pin_hasher.dart`（纯函数：加盐摘要 + 校验）
- 新增 `lib/data/repositories/lock_repository.dart`（读写 `app_state` 的锁相关键）
- 新增 `lib/pages/lock_screen.dart`、`lib/pages/app_lock_page.dart`、`lib/widgets/lock_gate.dart`
- `lib/main.dart`：用 `LockGate` 包住 `ShellPage`
- `lib/pages/settings_page.dart`：把「应用锁 M9」占位改成真实入口
- 依赖：新增 `crypto`（纯 Dart，SHA-256）
- 测试：哈希与校验、仓储、锁定页交互、设置流程、设备端回归
