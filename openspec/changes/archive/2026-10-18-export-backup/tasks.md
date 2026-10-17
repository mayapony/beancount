# Tasks

## 1. 数据出口

- [x] 1.1 `TransactionRepository.exportRows()` 返回 `ExportRow`（分类路径 / 账户名 / 标签 / 附件名），按发生时间升序；`test/data/transaction_repository_test.dart` 用例覆盖二级分类、无账户、多标签多附件
- [x] 1.2 `AttachmentRepository.allFiles()` 按文件名去重返回磁盘上的附件清单；用例覆盖同一文件被两笔账引用时只返回一份

## 2. CSV 写出

- [x] 2.1 新增 `beeCountCsvWriter.buildBeeCountCsv(rows)`：表头/列序/BOM/两位小数/时间格式与导入端一致；`test/services/export_csv_test.dart` 断言表头与单行取值
- [x] 2.2 往返用例：写 CSV → `parseBeeCountCsv` 读回，断言笔数/金额/分类/二级分类/账户/备注/标签一致
- [x] 2.3 边界用例：无标签无附件的行两列为空；导出空账本只得到表头

## 3. 备份打包

- [x] 3.1 新增 `ExportService.buildCsv()` / `buildBackup()`：返回文件名、字节、笔数、图片数；用例断言 zip 内同时含 `.csv` 与 `.tar.gz`
- [x] 3.2 往返用例：`buildBackup()` → `extractBeeCountExport()` → 图片字节与库里一致、共享图片只出现一份

## 4. 导出页与保存

- [x] 4.1 `ExportPage`：显示「N 笔 · M 张图」、两个导出按钮、进行中禁用与进度文案；`test/pages/export_page_test.dart` 覆盖渲染与状态
- [x] 4.2 保存走系统对话框：成功显示文件名/大小/位置；取消不落文件、不报成功；失败显示「导出失败：<原因>」；三个用例（注入假的 save 回调）
- [x] 4.3 文件名带时间戳：`beecount_YYYYMMDD_HHmmss.csv` / `beancount_backup_YYYYMMDD_HHmmss.zip`；用例断言格式与两次导出不同名

## 5. 接线与回归

- [x] 5.1 设置页「导出」从 `M8` 占位改为真实入口，进入 `ExportPage`；`test/pages/insights_assets_page_test.dart` 或新增用例断言入口可点
- [x] 5.2 `flutter analyze` 干净、`flutter test` 全绿（不低于 110 + 新增）
- [x] 5.3 设备端回归：导出 CSV 与完整备份到「下载」→ 清库 → 用导出的 zip 导入 → 笔数与图片数一致；结果写入 tasks.md

## 验证记录（2026-10-18）

- `flutter analyze`：No issues found
- `flutter test`：**132 通过**（上一轮 110 + 本次 22）
- `flutter test integration_test/export_roundtrip_test.dart -d emulator-5554`：通过
  - 设备真实文件系统上：3 笔账 + 2 张图 → 备份 zip → 写盘 → 读回 → 在空账本导入 → 3 笔 / 2 张图 / 金额与标签一致
- 人工真机（emulator-5554）验证 SAF 保存链路：
  - 设置 → 导出 → 「导出 CSV」→ 系统「另存为」对话框（Downloads）出现，默认文件名 `beecount_20261017_172825.csv`
  - 点 SAVE 后文件真的落盘：`/sdcard/Download/beecount_20261017_172825.csv`（104 B，空账本只有表头）
  - 页面显示成功卡片：文件名 + `104 B` + 目录
  - 取消 / 失败路径由 widget test 覆盖
- 说明：`FilePicker.saveFile` 是本轮唯一无法自动化的平台 API（系统对话框），因此在 Android 16 模拟器上人工验一次

## Workflow follow-up

- 归档 change：`openspec archive export-backup --yes`
- 归档后回写 `docs/PRODUCT_PLAN.md` §8（M8 状态）与 §14（划掉 `export-backup`）
