# Tasks

## 1. 数据层：按月查询

- [x] 1.1 `TransactionRepository.dayGroups` 增加 `year`/`month` 参数，用半开区间查询且月内不设上限；`test/data/transaction_repository_test.dart` 新增「跨月边界」与「单月 600 笔不截断」两条用例并跑绿
- [x] 1.2 `watchDayGroups` 透传月份参数，切月后流只发该月数据；用例：写入 9 月与 10 月各一笔，订阅 10 月只收到 1 笔

## 2. 数据层：读取单笔与编辑

- [x] 2.1 新增 `TransactionRepository.byId(id)` 返回 `TransactionRow?`；用例覆盖命中与不存在（返回 null）
- [x] 2.2 新增 `TransactionEdit` 输入与 `update()`：字段更新 + 标签重建（同名标签复用）；用例验证改金额/分类/账户/备注/标签后重新读取为新值
- [x] 2.3 `update()` 在金额/时间/备注变化时重算去重键，并排除自身冲突；用例：改成与另一笔同时间同金额同备注被拒绝且两笔都不变
- [x] 2.4 `update()` 只改分类/账户/标签时沿用原去重键；用例断言键未变、保存成功

## 3. 数据层：删除

- [x] 3.1 新增 `TransactionRepository.delete(id)`：事务内删交易（标签关联与附件记录随外键级联）；用例：删除后 `byId` 为 null、标签关联为 0、附件记录为 0
- [x] 3.2 删除前记录附件文件名，删除后按引用计数回收：唯一引用时文件消失，共享引用时保留；用例同时覆盖两种情形（`test/data/transaction_repository_test.dart` + `attachment_repository_test.dart`）

## 4. 明细页：按月浏览

- [x] 4.1 `TransactionsPage` 持有浏览月份状态并订阅该月数据，标题与概览随月份变化；`test/pages/transactions_page_test.dart` 用例：默认当月、切月后标题与合计变化
- [x] 4.2 区分两种空状态：整库无账「还没有记账」、当月无账「这个月还没有记账」+ 回到本月入口；两个用例
- [x] 4.3 新增 `MonthPickerSheet`（年步进 + 12 月网格 + 回到本月），点月份选中关闭；新增 `test/pages/month_picker_sheet_test.dart` 覆盖选中与回到本月
- [x] 4.4 明细列表支持左右滑动切月（速度阈值 200px/s），垂直滚动不受影响；用例：`fling` 后月份 ±1

## 5. 交易详情页与编辑

- [ ] 5.1 新增 `TransactionDetailPage`：金额、分类、账户、时间、备注、标签、图片缩略图；无图不渲染图片区、无账户省略该行；新增 `test/pages/transaction_detail_page_test.dart` 三条用例
- [ ] 5.2 `QuickEntrySheet` 增加可选 `initialDraft` 预填（金额/类型/分类/账户/时间/备注/标签），不传时行为不变；`test/widgets/quick_entry_sheet_test.dart` 补两条用例
- [ ] 5.3 详情页「编辑」打开预填面板，保存调用 `update()`，冲突时面板保持并提示；用例：改金额保存后明细更新、冲突保存被拒且数据不变
- [ ] 5.4 明细行可点进入详情页（保留缩略图点击看大图的独立热区）；用例：点行进入详情、点缩略图进入图片查看

## 6. 删除接线

- [ ] 6.1 详情页「删除」弹确认框（含金额），确认后删除并返回明细；用例：取消不变、确认后该行消失
- [ ] 6.2 删除后附件回收在页面上可观察（缩略图消失、文件被清理）；用例覆盖删除唯一引用图片的交易

## 7. 集成回归

- [ ] 7.1 `flutter analyze` 干净、`flutter test` 全绿（新增用例计入，不得低于当前 79 + 新增数）
- [ ] 7.2 模拟器回归：切到上个月 / 回到本月 / 编辑一笔真实账目 / 删除一笔带图账目 / 重启后数据一致；结果记录在本次变更说明里

## Workflow follow-up

- 归档 change：`openspec archive edit-and-browse-transactions --yes`，把 `ledger-editing` 与 `ledger-browsing` 增量并入 `openspec/specs/`
- 归档后回写 `docs/PRODUCT_PLAN.md` §8（M3 状态与「待补」）与 §14（划掉 `edit-and-browse-transactions`）
