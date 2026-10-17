# theme-preference Specification

## Purpose
让用户决定金豆长什么样：跟随系统、固定浅色或固定深色三选一，选完立刻生效并在下次打开时保持，设置页一眼能看到当前是哪种。

## Requirements

### Requirement: 主题 SHALL 支持三档并可持久化

用户 SHALL 能在「跟随系统 / 浅色 / 深色」之间选择；选择 SHALL 立即应用到整个 App，并在 App 重启后保持。偏好 SHALL 存在本地（`app_state`），无需登录或网络。

#### Scenario: 切到深色立刻生效

- **WHEN** 用户在设置里选「深色」
- **THEN** 当前界面立即变暗，无需重启

#### Scenario: 重启后仍是深色

- **WHEN** 用户选「深色」后完全关闭并重新打开 App
- **THEN** 打开后仍是深色，设置页显示「深色」

#### Scenario: 跟随系统

- **WHEN** 用户选「跟随系统」且系统处于深色模式
- **THEN** App 显示深色；系统切回浅色时 App 跟着变浅

### Requirement: 设置页 SHALL 显示并可修改当前主题

设置页的主题行 SHALL 显示当前档位的名字，点击 SHALL 弹出三选一（当前项有选中标记），选择后 SHALL 关闭面板并更新行尾文案。

#### Scenario: 显示当前值

- **WHEN** 当前偏好是「跟随系统」
- **THEN** 设置页主题行尾部显示「跟随系统」

#### Scenario: 修改入口

- **WHEN** 用户点击主题行
- **THEN** 弹出面板，包含三个选项且当前项带勾

### Requirement: 启动 MUST NOT 闪白或闪暗

App 启动时 SHALL 在读不到偏好前使用「跟随系统」，读到后再切换到已保存的值；MUST NOT 先按错误的主题渲染一整帧。

#### Scenario: 启动直接是保存的主题

- **WHEN** 用户偏好是深色，冷启动 App
- **THEN** 首屏就是深色，不会先出现一帧浅色
