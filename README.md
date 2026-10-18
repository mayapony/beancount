# 金豆 · Bean Count

> 一颗圆豆子 / 小种子，肚子里存金币 ——「种豆得钱」。

一个**本地优先、极简**的个人记账 App。四个 Tab：**明细 · 洞察 · 资产 · 设置**。
截图记账是自动能力（截屏后自动识别），不占独立入口。

## 状态

🟢 **1.0.1 已发布**：M1–M6、M8–M10 完成；M7 只完成「手动加图 → 本地 OCR 预填」，截屏自动触发与视觉模型仍为 Backlog；生物识别与「多账本」待决策。产品计划见 [`docs/PRODUCT_PLAN.md`](docs/PRODUCT_PLAN.md)，设计语言见 [`docs/DESIGN.md`](docs/DESIGN.md)。

## 技术栈

| 项 | 选型 |
|---|---|
| 框架 | Flutter 3.27.3 / Dart 3.6.1 |
| 图表 | fl_chart |
| 格式化 | intl（千分位 + 等宽数字） |
| 目标平台 | Android / iOS |
| 依赖源 | 国内镜像 `pub.flutter-io.cn` |

## 目录结构

```
bean-count/
├── docs/
│   ├── PRODUCT_PLAN.md   # 产品计划（11 个里程碑）
│   ├── DESIGN.md         # 设计语言基线
│   └── prd/_TEMPLATE.md  # PRD 模板
├── openspec/             # 研发规范
│   ├── specs/            # 已实现能力的「真相」
│   ├── changes/          # 变更提案
│   │   └── archive/      # 已归档变更
│   └── config.yaml       # 语言 = zh
├── .dsh/skills/          # DeepSeek Harness 的 OpenSpec 技能
├── lib/
│   ├── theme/            # tokens.dart（设计 token）+ app_theme.dart
│   ├── pages/            # 4 Tab + 设计规范 Demo
│   ├── widgets/          # 金豆 FAB、底部导航、通用组件
│   ├── data/             # Demo 假数据（M1 换真数据层）
│   └── utils/            # 金额格式化
└── test/
```

---

## 研发规范：OpenSpec + TDD

本项目用 **OpenSpec**（spec-driven development）管理「需求 → 实现」的全过程，并用 **TDD** 落地每个任务。
原则：**spec 是唯一真相；代码只是 spec 的实现；任何改动必须先有提案。**

### 1. 安装与初始化（已完成，换机时参考）

```powershell
# 安装 CLI（Node 环境）
npm install -g @fission-ai/openspec
openspec --version            # 1.14.x

# 在项目根目录初始化（生成 openspec/ 与 .dsh/skills/）
openspec init --tools dsh --language zh --no-animation
```

> `--tools dsh` 会为 DeepSeek Harness 生成 6 个技能；`--language zh` 把所有产物设为中文
> （结构标题与 SHALL/MUST 关键字保留英文，便于校验）。

### 2. 三个核心概念

| 概念 | 位置 | 作用 |
|---|---|---|
| **spec（真相）** | `openspec/specs/<capability>/spec.md` | 描述**已经实现**的行为，只能由归档写入 |
| **change（提案）** | `openspec/changes/<id>/` | 描述**打算做**的改动；实现完成前一直存在 |
| **archive（归档）** | `openspec/changes/archive/<id>/` | 完成后的变更，其增量已并入 specs |

一份 `change` 通常包含三件套：

```
openspec/changes/<id>/
├── proposal.md              # 为什么做 / 做什么 / 不做什么（范围与非范围）
├── tasks.md                 # 原子任务清单（每项 ≤2 小时，可勾选）
└── specs/<capability>/
    └── spec.md              # 行为增量（ADDED / MODIFIED / REMOVED + SHALL/MUST）
```

### 3. 一次变更的完整流程

```powershell
# ① 写 PRD（产品侧）
#    复制 docs/prd/_TEMPLATE.md → docs/prd/M1-数据基础层.md

# ② 开提案（用 kebab-case 命名，与里程碑对应）
openspec new change m1-data-foundation --description "drift 数据层与 Repository" --goal "M1 数据基础层"

# ③ 查看该提案需要写什么
openspec instructions --change m1-data-foundation

# ④ 按指令写 proposal.md / tasks.md / specs 增量（编辑器或 AI 完成）

# ⑤ 校验格式（严格模式）
openspec validate m1-data-foundation --strict

# ⑥ 实现（TDD）：对每个 task
#    先写失败的测试 → 让测试变绿 → 在 tasks.md 勾选
flutter test test/data/local_account_repository_test.dart

# ⑦ 查看完成状态（哪些产物齐了、任务勾了多少）
openspec status --change m1-data-foundation

# ⑧ 全部完成后归档：增量并入 specs/，change 移入 archive/
openspec archive m1-data-foundation
```

### 4. 常用命令速查

| 目的 | 命令 |
|---|---|
| 列出进行中的变更 | `openspec list` |
| 列出已实现的能力 | `openspec list --specs` |
| 打开总览仪表盘 | `openspec view` |
| 查看某个变更详情 | `openspec show <id>` |
| 校验单个变更（严格） | `openspec validate <id> --strict` |
| 校验全部变更与 spec | `openspec validate --all --strict` |
| 提交前检查归档是否漏任务 | `openspec validate --archived` |
| 项目健康检查 | `openspec doctor` |
| 更新 AI 指令文件 | `openspec update` |

### 5. 与 TDD 的配合约定

- **一个 task = 一组测试**。tasks.md 里每勾掉一条，对应测试必须已是绿的。
- 测试文件路径镜像 `lib/`：`lib/data/x.dart` → `test/data/x_test.dart`。
- 纯逻辑（金额、汇率、分类匹配）用 `test()`；页面用 `testWidgets()`。
- 提 PR 前必须：`flutter analyze` 零告警 + `flutter test` 全绿 + `openspec validate --all --strict` 通过。

### 6. 提交规范

提交信息与 PR 标题统一为 `<type>(<scope>): <中文描述>`：

- `feat` / `fix` / `refactor` / `test` / `docs` / `chore` / `perf`
- 示例：`feat(transaction): 支持收支转账三合一录入`
- 归档时单独提交：`chore(openspec): archive m1-data-foundation`

---

## 快速开始

```powershell
# 依赖
flutter pub get

# 运行（需先启动模拟器或连接真机）
flutter run

# 静态分析（必须零告警）
flutter analyze

# 测试
flutter test
```

> 依赖走国内镜像，若新终端未生效，先设置：
> `$env:PUB_HOSTED_URL = "https://pub.flutter-io.cn"`
> `$env:FLUTTER_STORAGE_BASE_URL = "https://storage.flutter-io.cn"`

## 设计规范 Demo

运行 App 后，**设置 → 设计规范 Demo**，可在真机上查看并敲定：
品牌色 / 语义色 / 分类色板 / 字阶 / 千分位金额 / 圆角 / 按钮 / 列表项 / 空状态 / 图表 / 暗色预览。
