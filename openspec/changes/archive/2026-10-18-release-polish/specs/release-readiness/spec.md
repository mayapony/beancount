# Spec Delta

## Purpose

让产品具备"可以装到别人手机上"的最小成品度：统一的品牌图标、在深色模式下没有看不清的文字、一条命令能出包、CI 能拦住打包失败，以及一条只拦灾难性退化的性能护栏。

## ADDED Requirements

### Requirement: 应用 SHALL 使用品牌图标

Android 的五个密度与 Web 的 192/512/遮罩图标、favicon SHALL 使用同一套「金豆」图案；图标 SHALL 由脚本从设计 token 的颜色生成，脚本 MUST 能从零重出全部尺寸。

#### Scenario: 图标不是 Flutter 默认

- **WHEN** 用户把 App 装到桌面
- **THEN** 图标是金豆图案（暖砂底 + 金色豆子），不是 Flutter 的蓝色 F

#### Scenario: 脚本可重出

- **WHEN** 有人改了图标配色并重新运行生成脚本
- **THEN** 五个密度与 Web 图标全部更新为同一套图案

### Requirement: 界面 SHALL 在深色模式下可读

四个 Tab、记账面板、详情页与设置各子页 SHALL 在深色模式下使用主题色，MUST NOT 出现"深色背景上的固定深色文字"或"深色背景上的白色硬编码块"；必要的固定色（如查看大图的黑底）SHALL 只用于明确的中性场景。

#### Scenario: 四个 Tab 暗色可构建

- **WHEN** 以深色主题构建 Shell 并切换四个 Tab
- **THEN** 没有构建异常，关键文字（Tab 名称、页面标题）存在

#### Scenario: 记账面板暗色可读

- **WHEN** 深色模式下打开记一笔面板
- **THEN** 金额、分类名、备注行都使用主题文字色，不出现黑字黑底

### Requirement: CI SHALL 校验可打包

持续集成 SHALL 在 analyze、test、openspec validate 之后执行一次 APK 构建；构建失败 SHALL 使该次检查失败。

#### Scenario: 平台配置坏了会红

- **WHEN** 有人改坏了 Android 清单或依赖配置
- **THEN** CI 的打包步骤失败，合并被拦下

### Requirement: 发版 SHALL 有一条命令

仓库 SHALL 提供一个脚本，一条命令产出 release APK 并打印产物路径与体积；脚本 MUST NOT 内置任何签名密钥。

#### Scenario: 一条命令出包

- **WHEN** 维护者在仓库根目录运行发版脚本
- **THEN** 生成 `build/app/outputs/flutter-apk/app-release.apk` 并输出其大小

### Requirement: 性能 SHALL 有护栏

系统 SHALL 提供一条性能护栏用例：在 1 万笔交易的库上执行「按月查询 + 关键词搜索」，耗时 MUST 低于一个宽松上限；用例只用于拦截数量级退化。

#### Scenario: 万笔库仍可查询

- **WHEN** 库中有 1 万笔交易，执行一次按月查询与一次关键词搜索
- **THEN** 两者合计在数秒内完成，用例通过
