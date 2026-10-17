# Spec Delta

## Purpose

给本地账本加一道只属于自己的门：开启后用 4–6 位 PIN 解锁，PIN 不以明文保存，连续输错要付出等待成本；关闭或修改 PIN 都必须先证明自己是本人。

## ADDED Requirements

### Requirement: 应用锁 SHALL 以 PIN 保护入口

开启应用锁后，App 冷启动时 SHALL 先显示锁定页，输入正确 PIN 后才能进入账本；未开启时 SHALL 直接进入。PIN SHALL 为 4–6 位数字。

#### Scenario: 开启后冷启动要解锁

- **WHEN** 用户开启应用锁并设置 PIN `1234`，随后完全关闭并重新打开 App
- **THEN** 首先看到锁定页，输入 `1234` 后才进入明细页

#### Scenario: 未开启直接进入

- **WHEN** 应用锁处于关闭状态
- **THEN** 打开 App 直接进入明细页，不出现锁定页

### Requirement: PIN MUST NOT 以明文保存

系统 SHALL 保存随机盐与「盐 + PIN 迭代散列」的摘要，MUST NOT 保存明文 PIN；验证时 SHALL 用同样方式计算摘要后比较。

#### Scenario: 存储里看不到明文

- **WHEN** 用户设置 PIN `2468`
- **THEN** 本地存储中不存在字符串 `2468`，只有盐与摘要

#### Scenario: 同一 PIN 两次设置得到不同摘要

- **WHEN** 用户先后两次设置同一个 PIN
- **THEN** 两次的摘要不同（盐随机）

### Requirement: 修改与关闭 SHALL 先验证旧 PIN

修改 PIN 或关闭应用锁时，系统 SHALL 先要求输入当前 PIN；验证失败 MUST NOT 修改任何状态。

#### Scenario: 旧 PIN 错误时拒绝修改

- **WHEN** 当前 PIN 为 `1234`，用户在修改流程中输入 `0000`
- **THEN** 修改被拒绝并提示 PIN 错误，PIN 仍为 `1234`

#### Scenario: 关闭后不再拦截

- **WHEN** 用户输入正确的当前 PIN 并关闭应用锁
- **THEN** 下次冷启动直接进入账本

### Requirement: 输入错误 SHALL 有限速

连续输错 PIN 时系统 SHALL 提示错误，连续 5 次失败后 SHALL 锁定输入 30 秒；锁定期间 MUST NOT 接受新的输入尝试。

#### Scenario: 连续错误后等待

- **WHEN** 用户连续 5 次输入错误 PIN
- **THEN** 界面提示剩余等待秒数，数字键盘不可用；30 秒后恢复可输入

#### Scenario: 正确输入清零计数

- **WHEN** 用户先输错 2 次，再输入正确 PIN
- **THEN** 解锁成功，错误计数归零

### Requirement: 离开 App 后 SHALL 重新上锁

应用锁开启时，App 退到后台超过 1 分钟后再回到前台 SHALL 重新要求解锁；1 分钟内回来 SHALL NOT 打扰用户。

#### Scenario: 短暂切走不打扰

- **WHEN** 用户解锁后切到其它 App，10 秒后回来
- **THEN** 仍然停留在离开前的页面，不需要再次解锁

#### Scenario: 长时间离开要重新解锁

- **WHEN** 用户解锁后切走 2 分钟再回来
- **THEN** 显示锁定页
