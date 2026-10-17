# Tasks

## 1. 数据出口

- [ ] 1.1 `TransactionRepository.exportRows()` 返回 `ExportRow`（分类路径 / 账户名 / 标签 / 附件名），按发生时间升序；`test/data/transaction_repository_test.dart` 用例覆盖二级分类、无账户、多标签多附件
- [ ] 1.2 `AttachmentRepository.allFiles()` 按文件名去重返回磁盘上的附件清单；用例覆盖同一文件被两笔账引用时只返回一份

## 2. CSV 写出

- [ ] 2.1 新增 `beeCountCsvWriter.buildBeeCountCsv(rows)`：表头/列序/BOM/两位小数/时间格式与导入端一致；`test/services/export_csv_test.dart` 断言表头与单行取值
- [ ] 2.2 往返用例：写 CSV → `parseBeeCountCsv` 读回，断言笔数/金额/分类/二级分类/账户/备注/标签一致
- [ ] 2.3 边界用例：无标签无附件的行两列为空；导出空账本只得到表头

## 3. 备份打包

- [ ] 3.1 新增 `ExportService.buildCsv()` / `buildBackup()`：返回文件名、字节、笔数、图片数；用例断言 zip 内同时含 `.csv` 与 `.tar.gz`
- [ ] 3.2 往返用例：`buildBackup()` → `extractBeeCountExport()` → 图片字节与库里一致、共享图片只出现一份

## 4. 导出页与保存

- [ ] 4.1 `ExportPage`：显示「N 笔 · M 张图」、两个导出按钮、进行中禁用与进度文案；`test/pages/export_page_test.dart` 覆盖渲染与状态
- [ ] 4.2 保存走系统对话框：成功显示文件名/大小/位置；取消不落文件、不报成功；失败显示「导出失败：<原因>」；三个用例（注入假的 save 回调）
- [ ] 4.3 文件名带时间戳：`beecount_YYYYMMDD_HHmmss.csv` / `beancount_backup_YYYYMMDD_HHmmss.zip`；用例断言格式与两次导出不同名

## 5. 接线与回归

- [ ] 5.1 设置页「导出」从 `M8` 占位改为真实入口，进入 `ExportPage`；`test/pages/insights_assets_page_test.dart` 或新增用例断言入口可点
- [ ] 5.2 `flutter analyze` 干净、`flutter test` 全绿（不低于 110 + 新增）
- [ ] 5.3 设备端回归：导出 CSV 与完整备份到「下载」→ 清库 → 用导出的 zip 导入 → 笔数与图片数一致；结果写入 tasks.md

## Workflow follow-up

- 归档 change：`openspec archive export-backup --yes`
- 归档后回写 `docs/PRODUCT_PLAN.md` §8（M8 状态）与 §14（划掉 `export-backup`）
