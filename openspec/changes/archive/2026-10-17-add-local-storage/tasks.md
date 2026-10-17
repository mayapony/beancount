# Tasks

## 1. 依赖与数据库骨架

- [x] 1.1 在 `pubspec.yaml` 加入 `drift`、`drift_flutter`（或 `sqlite3_flutter_libs`）、`build_runner`、`drift_dev`，执行 `flutter pub get` 并确认 `flutter analyze` 仍通过
- [x] 1.2 新建 `lib/data/db/app_database.dart`：定义 `Categories`、`Accounts`、`Tags`、`Transactions`、`TransactionTags`、`Attachments`、`AppState` 七张表与 `dedupe_key` 唯一索引，跑 `dart run build_runner build` 生成 `*.g.dart` 并提交，验证生成文件存在且 `flutter analyze` 无错
- [x] 1.3 实现 `DatabaseConnection`：移动端文件库、`kIsWeb` 时 `NativeDatabase.memory()`；用一次性单测 `test/data/db_open_test.dart` 验证两种实现都能打开并建表

## 2. 种子与分类数据化

- [x] 2.1 写 `lib/data/seed.dart`：12 个默认支出分类（颜色/图标与 `BeanColors` / `kCategoryIcons` 同序，固定 id）、6 个默认收入分类（工资/奖金/兼职/理财/红包/其他收入）、1 个初始余额为 0 的默认账户；在 `onCreate` 调用，验证单测里首次打开后分类数为 18（支出 12 + 收入 6）、重复打开不增加
- [x] 2.2 定义 `Category` / `Account` / `Tag` 领域模型与 `CategoryRepository`（含两级校验、被引用不可删）；单测覆盖"新增分类后可按名字查到""二级分类挂父分类""删除被引用分类被拒绝"
- [x] 2.3 把 `CategoryAvatar` 改为接收分类记录（`name`/`color`/`icon`），保留一个从旧 `categoryIndex` 映射到种子分类的兼容构造，验证现有页面截图与改前一致
- [x] 2.4 记一笔网格改为按当前收支类型查询分类（支出 12 个、收入 6 个），删除 `kQuickCategoryOrder`；验证切换类型后网格内容随之变化、新增分类后网格出现该项、截图更新

## 3. 交易写入与读取

- [x] 3.1 实现 `TransactionRepository.create()`：金额转分、计算 `dedupe_key`、写 `transactions` + `transaction_tags`，单测覆盖"38.5 → 3850""重复键返回已存在""两笔不同备注可写入"
- [x] 3.2 记一笔面板提交改走仓储：成功才关面板，失败保留输入并提示；用 widget test 验证失败时面板未关闭
- [x] 3.3 明细页改为读库并按天分组、显示小计与空状态；widget test 覆盖"保存后当天出现""空库显示还没有记账"
- [x] 3.4 实现 `app_state` 读写上次分类/账户/类型，`shell.dart` 用它初始化面板；单测验证写入后读取一致
- [x] 3.5 实现 `AttachmentRepository`：`<appDocs>/attachments/` 私有目录、先落盘再写记录、`attachmentsOf(transactionId)`、按引用计数删除文件；单测覆盖"写两张图后能读回""同一文件被两笔引用时删一笔文件仍在""删最后一笔文件消失"
- [x] 3.6 明细行展示 32×32 圆角缩略图（`cacheWidth` 限流），点击进入可横滑的大图页；widget test 验证有图显示缩略图、无图不占位

## 4. 统计与资产接库

- [x] 4.1 洞察页改为按分类聚合查询（一级分类上卷二级），替换 `demoCategoryStats`；widget test 断言总额等于库里支出之和
- [x] 4.2 资产页改为账户 + 交易推导余额（初始余额 + 收支），替换 `demoAccounts`；种子账户初始余额一律 0，单测覆盖"初始 1000.00 支出 38.50 → 961.50"与"默认账户初始为 0.00"
- [x] 4.3 删除页面里对 `demoDayGroups` / `demoCategoryStats` / `demoAccounts` 的引用（`demo_data.dart` 仅保留给种子与预览），用 `grep -r "demo_" lib/pages` 验证为零命中

## 5. 集成与回归

- [x] 5.1 `flutter analyze` 零告警、`flutter test` 全绿（含新增仓储单测与 widget test）
- [x] 5.2 Android 模拟器跑一遍：记账 → 杀进程重开 → 记录仍在；截图与 `docs/review/shots` 对照无回归
- [x] 5.3 Web 可编译可启动：条件导入 + `drift/wasm`，`web/sqlite3.wasm` 与 `web/drift_worker.dart.js` 已入库；README 注明「Web 仅预览、数据不持久」（浏览器里数据不进附件目录语义）
- [x] 5.4 更新 `docs/DESIGN.md` 尾部决策清单：分类改为数据、金额存分、去重键规则、附件落盘与引用计数、账户初始余额为 0
- [x] 5.5 附件链路由 `AttachmentRepository` 单测（写入 / 引用计数 / 孤儿清理）与明细页缩略图 widget test 覆盖；设备端「加图」待 M7 图片选择器接入后再回归

## Workflow follow-up

- 实现完成后按项目评审要求归档该 change（`openspec archive add-local-storage`）。
- 归档后确认 `openspec/specs/ledger-storage` 与 `ledger-taxonomy` 已生成。
