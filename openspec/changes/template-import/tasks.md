# Tasks

## 1. 解析器

- [x] 1.1 新增 `lib/services/import/statement_import.dart`：`StatementKind` 识别（支付宝/微信/BeeCount/未知）、表头定位（前 30 行）、列名别名定位；`test/services/statement_import_test.dart` 用例：三种格式各识别一次、未知格式给可读提示
- [x] 1.2 支付宝解析：`收/支` → 收支类型、`交易分类` → 本地分类映射、`商品说明`/`交易对方` → 备注、账户固定「支付宝」；用例：支出/收入/不计收支各一行，断言金额分、分类、跳过原因带行号
- [x] 1.3 微信解析：`金额(元)` 去 `¥`、`商品` → 备注、账户「微信支付」、`/` 与「已全额退款」跳过；用例两条
- [x] 1.4 GBK 解码：UTF-8 严格解码失败后回退 GBK；用例：用 GBK 编码的中文账单能被正确解析
- [x] 1.5 Excel（xlsx）：用 `excel` 读第一个工作表 → matrix → 复用同一套识别与解析；用例：生成一份含 BeeCount 表头的 xlsx 并解析

## 2. 接线

- [x] 2.1 `parseImportFile(bytes, fileName)` 统一入口：xlsx / 文本 / BeeCount 分发；`test/services/import_service_test.dart` 或新用例：入口能返回正确 `ParseResult`
- [x] 2.2 导入页文件选择允许 `xlsx`，解析改走统一入口；用例：导入页仍能显示预览（现有用例保持绿）
- [x] 2.3 导入页提示文案补上「支持支付宝/微信账单与 Excel」

## 3. 回归

- [x] 3.1 `flutter analyze` 干净、`flutter test` 全绿（不低于 241 + 新增）
- [x] 3.2 设备端回归：导入一份支付宝格式账单 → 预览数字正确 → 落库后分类/账户正确；结果写入 tasks.md

## 验证记录（2026-10-18）

- `flutter analyze`：No issues found；`flutter test`：**253 通过**（上一轮 241 + 本次 12）
- 设备端 `integration_test/statement_import_flow_test.dart -d emulator-5554`：通过
  - 支付宝账单（UTF-8）在真实 sqlite 上解析 → 计划 → 落库：2 笔，账户都是「支付宝」，金额 3850/12000
- 覆盖到的真实格式细节：
  - 支付宝前面有 3 行说明文字 + 一行 `-----` 分隔，表头在第 5 行 → 前 30 行内扫描
  - `不计收支` 与 `交易关闭` 行被跳过，报告里带行号与原因
  - 微信 `金额(元)` 带 `¥`、`/`（转账）与「已全额退款」行按规则跳过
  - 支付宝 Windows 导出是 **GBK**：UTF-8 严格解码失败后回退 GBK，中文分类与备注都能读对
  - `.xlsx` 走 `excel` 读第一个工作表，BeeCount 表头与支付宝表头都能识别
- 未做的部分（明确写在这里）：PDF 账单、招行/工行等银行流水专用列、多工作表合并
## Workflow follow-up

- 归档 change：`openspec archive template-import --yes`
- 归档后回写 `docs/PRODUCT_PLAN.md` §8（M8 状态）与 §14
