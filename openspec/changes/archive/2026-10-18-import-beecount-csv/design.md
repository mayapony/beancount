# Design

## Context

BeeCount 的导出实现（`D:\Code\BeeCount\lib\pages\data\export_page.dart`）决定了要兼容的真实格式，而不是 demo 目录里那份 7 列 CSV：

- 文件名 `beecount_<yyyyMMdd_HHmmss>.csv`，UTF-8 **带 BOM**，`\n` 换行；
- 表头随 App 语言本地化（zh：`类型,分类,二级分类,金额,币种,账户,转出账户,转入账户,备注,时间,标签,附件`）；
- 类型值是本地化文案（收入/支出/转账、Income/Expense/Transfer）；
- 分类名也会被本地化（`CategoryUtils.getDisplayName`），所以英文环境的导出可能是 `Food` 这类名字；
- 时间为 `YYYY-MM-DD HH:mm:ss`，导出时**前后各加两个空格**；
- 标签、附件都是逗号分隔的多值。

金豆侧的前提（来自 `add-local-storage`）：分类/账户/标签是数据，交易金额存整数分，`dedupe_key = hash(发生时间到秒, 金额分, trim(备注))` 唯一，附件有独立的 `attachments` 表并落在应用私有目录。

用户真实备份（2026-10-17，48 行）说明了"完整导出"长什么样：

- zip 内含 `beecount_20261017_201948.csv`（8.4 KB）与 `beecount_attachments_1792239580042.tar.gz`（17.5 MB）；
- tar 内有 `images/` 下 **46 张 jpg（解压后 19.6 MB）** 和一份 `metadata.json`（`version / exportedAt / count / attachments[{id, transactionId, fileName, originalName, fileSize, sortOrder, createdAt}]`，47 条记录）；
- 48 行里 **47 行带图、1 行不带**；其中两笔（同一秒、不同金额）**共用同一张图**；
- 分类 15 个且**二级分类全空**，账户 3 个，币种全 CNY，无重复行、无非法时间。

## Goals / Non-Goals

**Goals:**
- 一份真实导出（zip，含附件）能完整、可核对地进来，且可重复导入。
- 解析层与 UI 解耦：解析/映射/写入可单测，不依赖文件选择器。
- 单行坏数据不拖垮整批，问题可定位到行号。

**Non-Goals:**
- 不解析图片内容（不 OCR、不压缩、不生成缩略图），只把原始字节搬进私有目录。
- 不做币种换算；非 CNY 行按原数值导入并保留币种到备注。
- 不做通用 CSV 映射器（支付宝/微信账单）——只做 BeeCount 格式，其他格式后续独立变更。

## Decisions

### 1. 输入与解析：`archive` 解 zip/tar + `csv` 解析

- **入口**：用户选文件，接受 `.zip`（推荐，含附件）与裸 `.csv`（无图）。zip 用 `archive`（`ZipDecoder`）在内存解压：取第一个 `beecount_*.csv`，再找 `beecount_attachments_*.tar.gz` 交给 `GZipDecoder` + `TarDecoder`。
- 读字节 → 去掉 UTF-8 BOM（`\uFEFF`）→ `utf8.decode(allowMalformed: true)` → `CsvToListConverter(shouldParseNumbers: false, eol: '\n')`。
- **不使用** `shouldParseNumbers: true`：金额 `38.50` 会被解析成 double，精度在解析阶段就丢了；统一当字符串，再自己 `decimal → 分`。
- 表头做**别名映射**：`{类型: [类型, Type], 分类: [分类, Category], ...}`，按列名取值，缺列时报错并列出缺哪些。
- 时间：`trim()` 后按 `yyyy-MM-dd HH:mm:ss` 解析，失败再尝试 `yyyy/MM/dd HH:mm`。

### 2. 金额解析：字符串 → 分

正则 `^\d+(\.\d{1,2})?$` 校验后，拆整数与小数部分拼成整数分；不用 `double * 100`（`38.5 * 100 = 3849.999...`）。

### 3. 分类映射：自动创建 + 内存缓存

- 建立 `(name, type, parentName?)` → categoryId 的映射表，**先查本地、再查本批已创建**，避免 50 行重复建 50 个分类。
- 二级分类：先确保父分类存在，再建子分类；父分类类型取该行类型。
- 名称原样保留（含空格与英文名），不做大小写归一（BeeCount 允许同名不同大小写，金豆按原样存）。
- 类型冲突（同名分类在本地是"收入"、文件里是"支出"）→ 新建一个同名的另一类型分类，不修改已有记录。
- **与本地种子的重名**：真实数据里「餐饮 / 购物 / 居家 / 数码」与 12 个种子分类同名，必须复用种子记录（保留其颜色与图标），否则面板会出现两个「餐饮」。复用条件 = 同一 `type` + 同一 `name`。
- **账户**：新建账户的 `initial_balance_cents` 一律为 0（已确认），余额由导入的交易推导；不把 demo 余额带进来。

### 4. 写入：单事务分块 + 去重前置

- 每 200 行一个事务（避免超长事务与大 SQLite 变量上限），失败只回滚该块并记入报告。
- 去重：先在内存里用 `dedupeKey` 去重（文件内重复），再用 `INSERT OR IGNORE` + 唯一索引兜底（与库内重复）。
- 写入前先确保分类/账户/标签存在（同一事务内），保证外键有效。

### 5. 附件与币种

- **附件真导入**（决策已从"只记文件名"改为"搬运原始文件"）：
  - tar 内条目名是 `images/<fileName>`，CSV 附件列写的就是 `<fileName>`，按 basename 匹配；
  - 落盘走 `add-local-storage` 的 `AttachmentRepository`，文件名沿用 sha 原名；**同一文件名只写一次**，多条交易记录指向同一文件（真数据里就有两笔共用一张图）；
  - `metadata.json` 可选：有则用它的 `originalName` / `fileSize` 填充，无则 `originalName = fileName`；
  - CSV 提到但包里没有的图片 → **不算失败**，交易照常导入，报告记「附件缺失 N 个」；
  - 文件名含路径分隔符或 `..` → 跳过该附件并记 warning（防路径穿越）。
- **币种**：非空且不等于 CNY 时，金额照常导入，备注前加 `[USD]` 前缀；不做汇率。

### 5.1 附件对写入顺序与报告的影响

- 顺序：先写文件 → 再在事务内写交易与附件记录；文件写失败降级为"这笔无图 + warning"，不阻断整批。
- 报告新增一行：`附件 47 张 / 19.6 MB，缺失 0`。
- 预览页显示"将导入 47 张图片（约 19.6 MB）"，让用户对耗时与磁盘占用有预期。

### 6. UI：预览 → 写入 → 报告

- `设置 → 数据管理 → 从 BeeCount 导入` → `file_picker`（`FileType.custom`，允许 `zip` / `csv`）→ **预览页**（四段：可导入 / 跳过 / 将新建 / 图片数量与体积）→ 确认 → 进度 → **报告页**。
- 预览与写入共用同一个 `ImportPlan`，保证"预览看到的"就是"实际写入的"；取消预览不落库。
- 报告可复制：总数、成功、跳过按原因分组、失败行号明细、附件张数与缺失数。

### 7. 纯函数边界

`parseBeeCountCsv(String) → ParsedFile`、`buildImportPlan(ParsedFile, 现有数据) → ImportPlan`、`applyPlan(ImportPlan) → ImportReport` 三段都是纯逻辑（第三段依赖仓储），前两段可用 fixture 单测，不启动 UI。

## Risks / Trade-offs

- [BeeCount 未来改导出列] → 按列名取值 + 缺列报错，列顺序变化不影响；新增列被忽略。
- [分类名被本地化，导入后出现英文分类] → 保留原名是产品选择（用户已确认），不自动翻译；报告里提示"新建了 N 个分类"便于核对。
- [大文件（1 万行）性能与内存] → 解析后先按行生成轻量结构，再分块写入；目标 1 万行 < 3s，用 fixture 测。
- [去重键把真实的两笔同秒同额同备注交易判重] → 极少见；报告里给出"已存在"明细，用户可以改备注后单独补记。
- [导入期间 App 被杀] → 分块事务，已提交的块保留；重跑同一文件因幂等不会重复。
- [附件体积大，导入期间内存翻倍] → zip/tar 按条目流式取字节、逐张落盘；不把 19.6 MB 全部留在内存里。1 万行 + 大量图片时性能目标放宽为"完成即可，进度可见"。
- [图片落盘成功但交易事务回滚] → 先写文件后写记录，回滚会留下孤儿文件；导入结束后补偿清理"无引用的新文件"，并在报告里体现。
- [账户余额看起来"变少"] → 初始余额按 0 起算，报告里注明"余额由交易推导"。

## Open Questions

- 导入后是否自动跳到「明细」并定位到最早一条导入记录？（不影响 spec 与任务拆分，实施时按体验决定）
