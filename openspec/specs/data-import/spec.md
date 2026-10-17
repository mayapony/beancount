# data-import Specification

## Purpose
让用户把 BeeCount 导出的 CSV 账本安全地迁移进金豆：字段认得准、分类账户标签保真、重复导入不重复记账、每一行去哪了都有交代。

## Requirements

### Requirement: 系统 SHALL 识别 BeeCount 导出格式

系统 SHALL 读取 BeeCount 导出页生成的 CSV：UTF-8 带 BOM、逗号分隔、首行为表头、列顺序为 `类型,分类,二级分类,金额,币种,账户,转出账户,转入账户,备注,时间,标签,附件`。时间列 SHALL 允许首尾空格。当用户选择 BeeCount 的完整备份 `.zip` 时，系统 SHALL 从包内取 `beecount_*.csv` 与 `beecount_attachments_*.tar.gz`（后者按「附件」需求处理）；只选到 `.csv` 时 SHALL 视为"无附件导入"并照常完成。

#### Scenario: 识别标准导出文件

- **WHEN** 用户选择一个由 BeeCount 导出的 `beecount_20261017_221500.csv`
- **THEN** 系统成功解析出表头与全部数据行，并进入预览

#### Scenario: 选择完整备份 zip

- **WHEN** 用户选择含 `beecount_20261017_201948.csv` 与 `beecount_attachments_1792239580042.tar.gz` 的 zip
- **THEN** 系统解析出 CSV 的全部数据行，并把附件包一并识别为可导入的图片来源

#### Scenario: BOM 与空格不干扰

- **WHEN** 文件以 BOM 开头，且时间列值为 `  2026-10-17 12:30:00  `
- **THEN** 第一列名被正确识别为「类型」，时间被解析为 2026-10-17 12:30:00

### Requirement: 表头 SHALL 兼容中英文

BeeCount 的导出表头跟随 App 语言，系统 SHALL 同时接受中文与英文表头（Type/Category/Subcategory/Amount/Currency/Account/From Account/To Account/Note/Time/Tags/Attachments），并按列名而非列位置取值。

#### Scenario: 英文表头文件

- **WHEN** 导入的文件表头为 `Type,Category,Subcategory,Amount,...`
- **THEN** 系统按同样规则解析，不因表头语言而失败

#### Scenario: 缺少必需列

- **WHEN** 文件缺少「金额」列
- **THEN** 系统拒绝导入并提示缺少哪些必需列，不写入任何数据

### Requirement: 只导入收入与支出

系统 SHALL 只把类型为「收入 / Income」与「支出 / Expense」的行作为交易导入；「转账 / Transfer」行 SHALL 跳过，并在报告中单列数量与原因。

#### Scenario: 跳过转账行

- **WHEN** 文件中包含 3 行转账记录
- **THEN** 这 3 行不写入交易表，报告显示「跳过 3 行：转账暂不支持」

### Requirement: 分类 SHALL 自动创建并保留原名

导入时，分类列与二级分类列的名称 SHALL 原样保留：已存在同名同类型分类则复用，否则新建；有二级分类时 SHALL 在对应一级分类下建立二级分类，交易关联到二级分类。

#### Scenario: 新建一级分类

- **WHEN** 文件中出现分类「维修」，本地没有该分类
- **THEN** 新建支出分类「维修」，并将这些交易关联到它

#### Scenario: 二级分类挂到父分类

- **WHEN** 文件某行是「餐饮 / 午餐」，本地没有「午餐」
- **THEN** 「午餐」被创建为「餐饮」的子分类，交易关联到「午餐」

#### Scenario: 同名分类复用

- **WHEN** 文件中有 50 行都使用「餐饮」
- **THEN** 只创建或复用一个「餐饮」，不产生 50 个重复分类

### Requirement: 账户与标签 SHALL 自动创建

账户列、转出/转入账户列出现过的非空名称 SHALL 自动建为账户；标签列 SHALL 按逗号拆分后自动建标签，同名复用。

#### Scenario: 新建账户与标签

- **WHEN** 文件包含账户「支付宝」与标签「报销,出差」
- **THEN** 本地新增账户「支付宝」、标签「报销」与「出差」，交易正确关联

#### Scenario: 空账户名

- **WHEN** 某些行的账户列为空
- **THEN** 这些交易不带账户导入，不创建空名账户

### Requirement: 金额与时间 SHALL 精确解析

金额 SHALL 以两位小数解析并转成整数分；时间 SHALL 解析为本地时区的完整时间（到秒）。无法解析的行 MUST NOT 中止整批导入。

#### Scenario: 金额精度

- **WHEN** 某行金额为 `38.5`
- **THEN** 存储为 3850 分，导入后显示 38.50

#### Scenario: 单行时间非法

- **WHEN** 某行时间为空或格式非法
- **THEN** 该行被跳过，报告记录行号与原因，其余行继续导入

### Requirement: 导入 SHALL 幂等

导入 SHALL 复用交易的去重键；同一份文件导入第二次时 MUST 不新增任何重复交易，并在报告中说明跳过数量。

#### Scenario: 重复导入同一文件

- **WHEN** 用户把同一个文件连续导入两次
- **THEN** 第二次新增 0 条交易，报告显示「跳过 N 行：已存在」

#### Scenario: 部分重叠

- **WHEN** 新文件包含 100 行，其中 30 行与本地已有交易去重键相同
- **THEN** 导入 70 行、跳过 30 行，报告分别列出

### Requirement: 附件 SHALL 随交易原样导入

当导入源包含附件包时，系统 SHALL 把「附件」列中的文件名与包内 `images/<文件名>` 逐一匹配，将原始图片写入应用私有目录并关联到对应交易；同一文件名 MUST 只保存一份，被多笔交易引用时共享同一文件。附件缺失或文件名非法 MUST NOT 中止导入。

#### Scenario: 带图交易导入后可查看

- **WHEN** 某行附件列为 `sha_aaa.jpg`，附件包内存在 `images/sha_aaa.jpg`
- **THEN** 该笔交易导入后带有这张图片，明细里可看到缩略图并打开原图

#### Scenario: 两笔交易共用一张图

- **WHEN** 两行（同一时刻、不同金额）的附件列都是同一个 `sha_aaa.jpg`
- **THEN** 两笔交易都能看到这张图，磁盘上只保存一份

#### Scenario: 附件包缺失该文件

- **WHEN** 某行写明 `sha_missing.jpg`，但附件包内没有这个文件
- **THEN** 该笔交易照常导入（无图），报告记录「附件缺失 1 个」

#### Scenario: 只导入 CSV 不带附件

- **WHEN** 用户只选择 `.csv` 文件
- **THEN** 交易照常导入，报告注明「未包含附件包」，不视为失败

#### Scenario: 非法附件名

- **WHEN** 附件列出现 `../secret.jpg` 这类含路径穿越的文件名
- **THEN** 该附件被跳过并记入报告的警告，交易本身仍导入

### Requirement: 导入 SHALL 先预览后写入

写入前系统 SHALL 展示预览：可导入条数、将新建的分类/账户/标签清单、将跳过的条数与原因分类、将导入的图片张数与总大小；用户确认后才写入。

#### Scenario: 预览内容准确

- **WHEN** 用户选择文件后进入预览
- **THEN** 预览显示的行数与文件数据行数一致（可导入 + 跳过 = 总行数），未确认前数据库无新增

#### Scenario: 预览显示图片规模

- **WHEN** 备份 zip 内含 46 张图片、约 19.6 MB
- **THEN** 预览显示「将导入 46 张图片（约 19.6 MB）」，用户可据此判断耗时

#### Scenario: 取消导入

- **WHEN** 用户在预览页返回
- **THEN** 不写入任何数据，也不复制任何图片

### Requirement: 导入 SHALL 生成可核对的结果报告

导入完成后系统 SHALL 显示结果：成功条数、跳过条数（按原因分组）、失败条数与行号明细，并支持复制或导出报告文本。

#### Scenario: 报告含失败明细

- **WHEN** 导入中 2 行金额非法
- **THEN** 报告列出这 2 行的行号与原因，成功条数不受影响

#### Scenario: 报告可复制

- **WHEN** 用户点击「复制报告」
- **THEN** 报告文本进入剪贴板，包含总数、跳过原因与失败行号
