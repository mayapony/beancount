# data-export Specification

## Purpose
把本地账本带出 App：导出一份能被重新导入的 CSV，或一个含全部票据图片的完整备份包；导出过程不损坏、不残留，用户始终知道文件在哪。

## Requirements

### Requirement: CSV 导出 SHALL 与导入格式一致

导出的 CSV SHALL 使用与导入相同的表头与取值规则：列顺序为 `类型,分类,二级分类,金额,币种,账户,转出账户,转入账户,备注,时间,标签,附件`；文件 SHALL 为 UTF-8 带 BOM、逗号分隔、以 `\n` 换行；金额 SHALL 保留两位小数；时间 SHALL 为 `YYYY-MM-DD HH:mm:ss`；多个标签或附件名 SHALL 以逗号分隔。

#### Scenario: 导出后能被自己读回来

- **WHEN** 用户导出 CSV，再把它导入回一个空账本
- **THEN** 解析得到的笔数、金额、分类、账户、备注、标签与原账本一致

#### Scenario: 二级分类不丢层

- **WHEN** 一笔账的记账分类是「餐饮 / 外卖」
- **THEN** 导出行的「分类」为餐饮、「二级分类」为外卖

#### Scenario: 无标签无附件时留空

- **WHEN** 一笔账没有标签也没有图片
- **THEN** 该行的「标签」「附件」两列为空字符串，而不是 `null` 或 `[]`

### Requirement: 完整备份 SHALL 包含账本与全部图片

完整备份 SHALL 是一个 zip，内含与 CSV 同内容的时间戳 CSV 文件和 `beecount_attachments_<时间戳>.tar.gz`；后者 SHALL 包含 `images/` 目录下的全部票据文件，文件名与 CSV「附件」列一致。备份 MUST NOT 遗漏任何一笔账或任何一张被引用的图片。

#### Scenario: 备份往返保住图片

- **WHEN** 用户导出完整备份，在一个空账本上导入该 zip
- **THEN** 交易笔数、金额与图片数量与备份前一致，且图片内容可打开

#### Scenario: 共享图片只打一份

- **WHEN** 两笔账引用同一张图片
- **THEN** 备份包内该图片只出现一份，导入后两笔账都仍能看到它

### Requirement: 导出 SHALL 由用户选择保存位置

导出 SHALL 打开系统保存对话框让用户指定文件名与位置；用户取消时 MUST NOT 产生任何文件；写入失败时 SHALL 提示可读的错误原因，并清理已写出的临时文件。

#### Scenario: 取消不落文件

- **WHEN** 用户在保存对话框点取消
- **THEN** 设备上不新增任何导出文件，页面停留在可再次导出的状态

#### Scenario: 写入失败给出原因

- **WHEN** 目标位置不可写（例如权限不足）
- **THEN** 页面显示失败原因，不显示成功提示，也不留下半个文件

### Requirement: 导出前 SHALL 显示将要导出的规模

导出页 SHALL 展示当前账本的交易笔数与图片张数，并在导出进行中禁用按钮、显示进度，避免重复触发。

#### Scenario: 规模一目了然

- **WHEN** 用户打开导出页且账本里有 48 笔账、46 张图
- **THEN** 页面显示「48 笔 · 46 张图」，不给用户「导出了一份空文件」的意外

#### Scenario: 导出中不可重复点

- **WHEN** 用户点了「完整备份」且正在打包
- **THEN** 两个导出按钮都不可再次点击，直到本次结束

### Requirement: 导出文件名 SHALL 带时间戳

导出的文件 SHALL 以本地时间戳命名，避免同名覆盖：CSV 为 `beecount_YYYYMMDD_HHmmss.csv`，备份为 `beancount_backup_YYYYMMDD_HHmmss.zip`。

#### Scenario: 连续两次导出不覆盖

- **WHEN** 用户在同一天导出两次
- **THEN** 两个文件的时间戳不同，互不覆盖
