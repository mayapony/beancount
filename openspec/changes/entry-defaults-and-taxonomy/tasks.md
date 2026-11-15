# Tasks

## 1. 分类库作为唯一供给来源

- [x] 1.1 `lib/data/category_library.dart` 增加 `libraryRootToLedger` 映射与 `librarySeedRoots()`（一级 + 二级摊平、带图标与配色），标注「数码电器 / 健身运动」不建
- [x] 1.2 `lib/data/seed.dart` 的 `seedDefaults` 改为调用 `seedCategoryLibrary`，空库首启即写入 14 个一级 + 44 个二级 + 7 个收入分类
- [x] 1.3 `app_database.dart` schemaVersion 6 → 7，`onUpgrade(from < 7)` 调用同一个函数做增量补齐（幂等）
- [x] 1.4 单测：空库首启分类数量与「餐饮」下二级数量正确；重复执行 `seedCategoryLibrary` 不产生重复行
- [x] 1.5 单测：模拟老账本（只有 12 个一级）升级，已有分类 id/名称/颜色不变，新增二级挂在正确父级

## 2. 自动新建配额改口径

- [x] 2.1 `AutoCreatePolicy` 去掉 `categoryTotal` 入参，改读 `app_state.auto_create_category_ids`；`markCategoryCreated` 增加分类 id 参数
- [x] 2.2 三个调用点（`shell.dart` 面板、`capture_entry_saver.dart`、`screenshot/auto_entry.dart`）传入刚创建的分类 id
- [x] 2.3 单测：账本已有 60 个种子分类、自动创建计数为 0 时仍允许新建；计数到 40 后拒绝

## 3. 默认类型固定为支出

- [x] 3.1 `shell.dart` 打开面板时 `initialIsIncome` 恒为 `false`，`LastEntrySelection` 仍保存 `isIncome` 供别处使用但不再作为初始值
- [x] 3.2 单测：上一笔是收入时打开面板，默认选中「支出」

## 4. 来源应用写成标签

- [x] 4.1 `CaptureEntrySaver.save()` 与 `AutoScreenshotSaver.save()` 把 `sourceAppName(sourcePackage)` 追加进 tags（不受自动打标签开关影响）
- [x] 4.2 单测：来源为京东 → 交易关联「京东」标签；来源为空 → 不关联；已有同名标签 → 复用不新建
- [x] 4.3 单测：关闭自动打标签后自动入账仍带来源标签

## 5. 「待处理」随账户补齐清除

- [ ] 5.1 `update()` 写入时按 `input.accountId` 决定清标记（非空 → `Value(null)`，为空 → `Value.absent()`）
- [ ] 5.2 `onUpgrade(from < 7)` 增加一次性修复：`account_id IS NOT NULL AND needs_review = 1` 的行清标记
- [ ] 5.3 单测：详情页改账户保存后 `needsReview` 变 null；只改金额时保持原值
- [ ] 5.4 配件/详情页无回归：编辑不触发去重键冲突、金额与时间照旧更新

## 6. 门禁

- [ ] 6.1 `flutter analyze` 无告警、全量测试绿（`--exclude-tags screenshots`）
- [ ] 6.2 debug / release 两种 gradle 构建均可打包
- [ ] 6.3 `openspec validate --all --strict` 全绿
- [ ] 6.4 真机：升级安装后分类树变宽且旧分类名不变；面板能点到二级分类；「最近自动记账」里 3 条历史遗留的待处理标记消失
