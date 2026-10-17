# Proposal

## Why

明细页目前只有「新增」一条路：金额打错、分类选错、账户认错，都只能删库重来——48 笔真实账目进来之后，这是个每天都在的挫败点。
同时顶部「切换月份」按钮是 `onTap: () {}` 的空实现，列表一次读全库 500 条，账目攒够一年就再也看不清「这个月花了多少」。

## What Changes

- **交易详情页**（新）：点明细任意一行进入，展示金额、收支类型、分类、账户、时间、备注、标签与图片；图片可点开大图。
- **编辑一笔账**：详情页「编辑」复用记一笔面板并预填现值（金额/类型/分类/账户/时间/备注/标签），保存后明细、洞察、资产三处自动刷新；去重键按新值重算。
- **删除一笔账**：详情页「删除」二次确认后删除交易与其标签关联；交易图片按引用计数回收（最后一条引用才删磁盘文件）。
- **按月浏览**：明细页默认展示当月；点月份按钮打开「年 + 月」选择器（含「回到本月」），也可左右滑动切月；标题始终显示当前浏览的月份。
- **按月查询**：仓储新增月范围查询，明细只读该月数据，取代当前「全库 500 条」。
- **空状态分两种**：整库无账 → 「还没有记账」；当前月无账 → 「这个月还没有记账」并给回本月入口。

非目标（不属本次范围）：转账、搜索与筛选、编辑时增删图片、批量选择/删除、删除撤销、跨月汇总对比。

## Capabilities

### New Capabilities

- `ledger-editing`: 单笔交易的查看、编辑与删除，含金额/分类/账户/时间的修改、去重键维护与图片引用回收
- `ledger-browsing`: 明细按时间范围（月）浏览，含月份选择器、空月状态与范围切换

### Modified Capabilities

（无：`ledger-storage` 的既有需求不变，本次只是把它已声明的「图片随交易回收」真正实现。）

## Impact

- `lib/data/repositories/transaction_repository.dart`：新增 `byId` / `update` / `delete`，`dayGroups` 与 `watchDayGroups` 增加月份参数
- `lib/data/repositories/attachment_repository.dart`：删除交易时复用 `removeForTransaction`（已有）做引用回收
- `lib/pages/transactions_page.dart`：持有「当前浏览月份」状态，行可点，标题与概览随月份变化
- 新增 `lib/pages/transaction_detail_page.dart`、`lib/widgets/month_picker_sheet.dart`
- `lib/widgets/quick_entry_sheet.dart`：支持传入初始草稿（编辑模式），不改变新增模式的默认行为
- 测试：`test/data/transaction_repository_test.dart`、`test/pages/transactions_page_test.dart` 扩展；新增详情页与月份选择器用例
- 无新增第三方依赖
