# Tasks

## 1. 数据模型与迁移

- [x] 1.1 新增 `recurring_rules` 表（类型/金额/分类/两端账户/备注/每月几号/起始月/启用）与 `schemaVersion = 3` 的 v2→v3 迁移（建表）；`test/data/db_migration_test.dart` 增加「v1 直接升到 v3」用例：表存在、历史交易与索引不受影响
- [x] 1.2 `dedupeKeyFor` 增加可选 `salt`（循环补记传 `rule:<id>:<yyyy-MM>`）；用例：同 salt 稳定、不同 salt 不同、传空 salt 时键与旧公式一致

## 2. 规则仓储

- [x] 2.1 `RecurringRepository`：`all() / byId / create / update / setEnabled / delete`；用例覆盖增删改与默认启用
- [x] 2.2 纯函数 `occurrencesBetween(rule, from, to, now)`：每月指定日、29–31 落到月末、当月未到日子不补；用例覆盖 31 号在 2 月、10 月 3 日时不补 10 月
- [x] 2.3 `nextDueDate(rule, now)` 供列表展示下次执行日；用例：5 号规则在 8 号当天 → 下月 5 号

## 3. 补记服务

- [x] 3.1 `RecurringService.applyDue(now)`：逐规则逐期生成交易（复用 `TransactionRepository.create`），返回 `created / skipped`；用例：起始 7 月、10 月首启补 4 笔
- [x] 3.2 幂等：再执行一次 `created = 0`、交易总数不变；暂停的规则不补；用例三条
- [x] 3.3 转账规则补记：生成的是转账（两端账户），且不上收支统计；用例一条
- [x] 3.4 补记出的交易可正常编辑/删除，规则不受影响；用例：改金额后规则金额不变

## 4. 规则管理界面

- [x] 4.1 `RecurringPage`：列出规则（备注、周期描述、金额、下次执行、暂停标记）；`test/pages/recurring_page_test.dart` 断言渲染与排序
- [x] 4.2 新建/编辑面板：类型分段、金额、分类或两端账户、每月几号胶囊（1–28 + 月末）、备注、启用开关；用例覆盖新建一条支出规则
- [x] 4.3 暂停/删除：暂停后列表标记变化，删除后消失；两个用例

## 5. 备注历史

- [x] 5.1 `TransactionRepository.recentNotes(limit)`：去重、按最近使用倒序；用例覆盖去重与空账本
- [x] 5.2 备注弹窗加「最近用过」胶囊，点选填入；`test/widgets/quick_entry_sheet_test.dart` 用例：有历史时点选生效、无历史不显示

## 6. 接线与回归

- [x] 6.1 设置页新增「循环记账」入口；Shell 启动时执行一次 `applyDue`（不阻塞首帧、失败不影响启动）；用例：入口可点
- [x] 6.2 `flutter analyze` 干净、`flutter test` 全绿（不低于 185 + 新增）
- [ ] 6.3 设备端回归：v2 库升 v3、新建房租规则 → 重启补记 → 明细可见 → 暂停后不再补；结果写入 tasks.md

## Workflow follow-up

- 归档 change：`openspec archive recurring-transactions --yes`
- 归档后回写 `docs/PRODUCT_PLAN.md` §8（M4 状态）与 §14
