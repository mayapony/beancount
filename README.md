# 金豆 · Bean Count

> 一颗圆豆子 / 小种子，肚子里存金币 ——「种豆得钱」。

一个**本地优先、极简**的个人记账 App。四个 Tab：**明细 · 洞察 · 资产 · AI 截图记账**。

## 状态

🟡 规划阶段（尚未开始实现）。产品计划见 [`docs/PRODUCT_PLAN.md`](docs/PRODUCT_PLAN.md)。

## 目录结构

```
bean-count/
├── docs/            # 产品计划等文档
├── openspec/        # OpenSpec：specs/（真相）+ changes/（变更提案）
│   ├── specs/
│   ├── changes/
│   └── config.yaml
├── .dsh/            # DeepSeek Harness 的 OpenSpec 技能适配
└── (待 flutter create 后生成 lib/、android/ 等)
```

## 研发规范

- **OpenSpec + TDD**：一份 PRD → 一个 change 提案 → 任务拆分 → 测试先行实现 → 归档为 spec。
- 所有 spec / 提案 / 文档使用**中文**（OpenSpec 结构标题与 SHALL/MUST 关键字保留英文）。
- 依赖源使用国内镜像 `pub.flutter-io.cn`。

## 快速开始

```powershell
# 依赖（Flutter 项目建立后）
flutter pub get

# 测试
flutter test
```
