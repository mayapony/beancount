# Tasks

## 1. 两级选择器（记一笔面板）

- [x] 1.1 面板新增 `_childrenOf` 与「当前展开的一级」状态：选中一级后展示其二级区；无子分类的一级直接选中
  - 验证：`test/widgets/quick_entry_sheet_test.dart` 断言选「出行交通」后出现其二级、选空二级的一级时二级区不渲染
- [x] 1.2 二级区做成单行横向滚动胶囊，选中二级时落 `_categoryId = 二级 id`，一级仍高亮
  - 验证：单测断言选中二级后保存草稿里的分类是二级 id
- [x] 1.3 一级区与二级区各加「新增」：一级建一级分类，二级以当前一级为父级建二级；沿用「保存时才落库」
  - 验证：单测断言二级新增后草稿带 `newCategoryName` 与父级 id；取消记账不创建分类
- [x] 1.4 编辑一笔已有二级分类的账时，面板展开其父级并高亮该二级
  - 验证：单测用带二级分类的初始草稿，断言展开与高亮正确

## 1.5 分类库（新增：参考一木记账）

- [x] 1.5 内置分类库：常见一级 + 二级分类，带图标 key 与搜索别名；按收支类型过滤
  - 验证：`test/data/category_library_test.dart` 覆盖按名字/别名/父级搜索、类型过滤、每条都有图标
- [x] 1.6 新增分类改成「库选择器」：搜索框 + 库列表（显示父级路径、已有置灰）+ 搜不到时可自定义新建；选二级时自动补建父级
  - 验证：面板单测断言选「出行交通 / 加油」会先建父级再建二级

## 2. 分类树进提示词

- [x] 2.1 `VisionReceiptRecognizer` 接收分类树（一级 → 二级名列表），提示词按「一级（二级、二级）/ 一级」渲染；不再使用硬编码 `kCategoryKeywords`
  - 验证：单测断言自建分类「日用品」出现在提示词里、二级名出现在对应父级括号内
- [x] 2.2 `systemReceiptRecognizer` 从 `CategoryRepository` 读真实分类树并传入
  - 验证：工厂单测断言传入的分类被渲染进提示词

## 3. 缺分类时自动新建

- [x] 3.1 前台面板：识别出账本没有的分类名时，按 `AutoCreatePolicy` 判定能否新建；允许则显示「将新建」并在保存时创建、记配额
  - 验证：`test/services/ocr/auto_create_policy_test.dart` 与面板单测覆盖「允许 / 开关关闭 / 配额用尽」
- [x] 3.2 后台自动入账（`AutoScreenshotSaver`）：匹配不到分类时同样走开关 + 配额，允许则 `ensure` 新建并记配额，不允许则按既有兜底
  - 验证：`test/services/screenshot/auto_entry_test.dart` 断言开关关闭不建、配额充足时新建且落该分类
- [x] 3.3 无障碍/通知入账路径（`CaptureEntrySaver`）复用同一解析，缺分类时同样受配额约束
  - 验证：`test/services/capture/capture_runtime_test.dart` 断言存在分类树时优先落到匹配分类

## 4. 门禁

- [ ] 4.1 `flutter analyze` 零告警、`flutter test --exclude-tags screenshots` 全绿、`assembleDebug` / `assembleRelease` 构建成功、`openspec validate --all --strict` 通过
  - 验证：四条命令输出贴进提交说明
- [ ] 4.2 真机：面板选二级 → 记一笔 → 明细按一级汇总；截图识别自建分类 → 落对分类
  - 验证：真机截图 + `adb pull` 的 `events.log`

## Workflow follow-up

- 归档前回写 `openspec/specs/ledger-taxonomy/spec.md` 与 `docs/PRODUCT_PLAN.md`。
