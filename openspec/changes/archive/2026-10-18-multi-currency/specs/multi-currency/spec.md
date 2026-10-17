# Spec Delta

## Purpose

让外币消费既能按原样留档、又能按本位币参与统计：账户带币种，外币交易记录原币金额与当时的汇率，所有汇总仍以本位币为准，明细里同时给出原币与折合金额。

## ADDED Requirements

### Requirement: 账户 SHALL 带币种

每个账户 SHALL 有一个币种（ISO 代码，默认 `CNY`）；账户管理里 SHALL 能选择币种，且 SHALL 显示在账户行上。

#### Scenario: 新建外币账户

- **WHEN** 用户新建账户并选择币种 `USD`
- **THEN** 该账户行显示 `USD`，之后用它记账时默认按外币录入

#### Scenario: 默认是本位币

- **WHEN** 用户不选币种直接新建账户
- **THEN** 该账户币种是 `CNY`

### Requirement: 外币交易 SHALL 记录原币金额与汇率

当交易币种不是 `CNY` 时，系统 SHALL 保存原币金额、币种与汇率（1 单位外币 = 多少 CNY，存为 ppm 整数），并 SHALL 用汇率换算出本位币金额写入原有金额字段。

#### Scenario: USD 100 @ 7.25

- **WHEN** 用户在某 USD 账户记一笔 100.00，汇率 7.25
- **THEN** 交易保存原币 10000 分、币种 USD、汇率 7250000，本位币金额 72500 分

#### Scenario: 统计用本位币

- **WHEN** 上述 USD 交易与一笔 100 元 CNY 支出在同一个月
- **THEN** 该月支出合计是 825 元（725 + 100）

#### Scenario: 汇率必须为正

- **WHEN** 用户把汇率填成 0 或负数
- **THEN** 保存被拒绝并提示

### Requirement: 明细 SHALL 显示折合金额

明细行与交易详情 SHALL 对非 CNY 交易显示原币金额，并同时给出折合后的本位币金额；CNY 交易 SHALL 保持现状（只显示一个金额）。

#### Scenario: 明细里看到原币

- **WHEN** 明细里有一笔 USD 100 @ 7.25
- **THEN** 金额处显示 USD 100.00，并附有约 ¥725.00

#### Scenario: 详情里看到汇率

- **WHEN** 打开这笔交易的详情
- **THEN** 能看到原币金额、汇率与折合后的本位币金额

### Requirement: 汇率 SHALL 记住上次的值

同一币种 SHALL 记住上次使用的汇率（存在 `app_state`），下次记该币种的账时作为默认值，用户仍可修改。

#### Scenario: 第二次记 USD 账

- **WHEN** 用户上次用 7.25 记过 USD，这次再记一笔 USD
- **THEN** 汇率默认填 7.25

### Requirement: 导出 MUST NOT 丢失金额

导出 CSV 时非 CNY 交易 SHALL 写本位币金额与 `CNY` 币种；MUST NOT 写出会让重新导入后金额翻倍或错位的数值。原币金额与汇率不进入导出（已知限制）。

#### Scenario: 导出外币交易

- **WHEN** 导出一笔 USD 100 @ 7.25 的交易
- **THEN** CSV 里金额是 725.00、币种是 CNY
