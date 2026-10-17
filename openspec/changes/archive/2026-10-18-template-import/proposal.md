# Proposal

## Why

想从别的记账 App 迁过来的人，手上通常只有一份**银行/支付平台的账单**：支付宝导出的 GBK CSV、微信支付的账单 CSV，
或者一张从 Excel 里导出的表。现在导入页只认 BeeCount 自己的格式，这些人第一步就卡住——M8 缺的就是这块。

## What Changes

- **格式自动识别**：按内容判断是 BeeCount 导出、支付宝账单、微信支付账单还是 Excel 表格，用户不需要先选格式。
- **支付宝账单**：跳过几行说明文字找到表头；映射 `交易分类` → 本地分类（餐饮美食→餐饮、交通出行→交通……）；`不计收支` 与退款行跳过并给出行号原因。
- **微信支付账单**：同样跳过前言与页脚；`/`（中性）与「已全额退款」行跳过。
- **GBK 兼容**：支付宝导出的是 GBK，先按 UTF-8 解、失败再按 GBK 解，避免整份文件变乱码。
- **Excel（.xlsx）**：读第一个工作表，表头匹配 BeeCount 或支付宝/微信的列名后走同一套解析与落库。
- 解析结果仍产出既有的 `ParsedRow`，所以**预览、去重、报告、附件**全部复用，不写第二套导入逻辑。
- 非目标：PDF 账单、银行流水（招行/工行）专用格式、多工作表合并、自动抓取邮件账单。

## Capabilities

### New Capabilities

- `statement-import`: 支付宝/微信账单与 Excel 表格的识别、字段映射与跳过规则

### Modified Capabilities

（无：导入流水线、去重与报告语义不变，本次只是多了几种输入。）

## Impact

- 新增 `lib/services/import/statement_import.dart`（识别 + 支付宝/微信解析 + GBK 解码 + xlsx 读取）
- `lib/pages/import_page.dart`：文件选择支持 `xlsx`，改用统一入口解析
- 依赖：新增 `excel`（读 xlsx）与 `gbk_codec`（解支付宝的 GBK）
- 测试：支付宝/微信/Excel 三套解析用例（含跳行与分类映射）、GBK 用例、设备端回归
