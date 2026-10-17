# Tasks

## 1. 仓储：筛选与搜索

- [x] 1.1 新增 `LedgerFilter`（关键词/类型/时间范围/分类/账户/标签/金额区间）与 `SearchRange` 枚举；`test/data/transaction_search_test.dart` 覆盖各条件的默认值
- [x] 1.2 `searchLedger(filter)`：SQL 收敛 type / 时间 / 分类（含子分类）/ 账户 / 金额；用例逐条验证（类型、时间边界、分类含子级、账户、金额上下限）
- [x] 1.3 关键词在内存匹配备注 / 分类名 / 账户名 / 标签，大小写不敏感；用例：按备注、按分类名、按标签、按账户名各一条
- [x] 1.4 组合条件为「同时满足」，并返回按日分组的结果与命中总数；用例：类型 + 时间 + 分类组合、以及互斥条件返回空
- [x] 1.5 结果上限 2000 条并给出是否被截断的标志；用例：插入 2001 笔时 `truncated` 为真、返回 2000 条

## 2. 抽出日分组列表

- [x] 2.1 把明细页的日分组与行渲染抽到 `lib/widgets/ledger_day_list.dart`（`LedgerDayList`），明细页改用它且现有 widget test 全绿
- [x] 2.2 抽出后的行仍支持：点行进入详情、点缩略图看大图；用例沿用明细页的两条导航测试

## 3. 搜索页

- [x] 3.1 `SearchPage`：输入框 + 类型/时间快捷胶囊 + 结果列表；`test/pages/search_page_test.dart` 覆盖输入即搜与空结果文案
- [x] 3.2 关键词/类型/时间组合：改变条件后结果数量与文案随之变化（用例覆盖支出、近三月）
- [x] 3.3 「筛选」面板：分类、账户、标签、金额区间；用例覆盖分类筛选与金额区间
- [x] 3.4 筛选摘要：显示已生效条件、单条移除、一键清空（关键词保留）；三条用例
- [x] 3.5 结果行点击进入交易详情；用例：点结果行打开详情页

## 4. 入口与回归

- [x] 4.1 明细页标题栏新增搜索入口，点开进入 `SearchPage`；用例：点放大镜进入搜索页
- [x] 4.2 `flutter analyze` 干净、`flutter test` 全绿（不低于 154 + 新增）
- [x] 4.3 设备端回归：搜索关键词、按类型 + 时间筛选、分类 + 金额区间、从结果改一笔再返回；结果写入 tasks.md

## 验证记录（2026-10-18）

- `flutter analyze`：No issues found
- `flutter test`：**169 通过**（上一轮 154 + 本次 15）
- `flutter test integration_test/search_flow_test.dart -d emulator-5554`：通过（真实文件库）
  - 初始命中 3 笔 → 关键词「超市」收敛到 1 笔 → 清空关键词切「收入」得 1 笔 → 「全部收支」后进筛选面板选「购物」+ 金额 100–300 → 命中 1 笔 → 点进详情把分类改成「餐饮」→ 返回后原筛选不再命中（命中 0 笔 + 空状态）
- 过程中修掉的两个测试/UI 问题：
  - 筛选面板的分类一多会把「应用」顶出屏幕 → 改成「筛选条件可滚 + 操作行固定底部」
  - 测试里 `find.byType(TextField).at(0)` 命中的是搜索框而不是金额输入框 → 改为按标签定位（`widgetWithText(TextField, '最小')`）

## Workflow follow-up

- 归档 change：`openspec archive search-and-filter --yes`
- 归档后回写 `docs/PRODUCT_PLAN.md` §8（M3 状态）与 §14
