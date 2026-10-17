# Proposal

## Why

出国刷一笔 USD 100，现在只能折成人民币记，原始金额和汇率都没留下——事后想核对"这顿 18 欧到底扣了多少"就无从查起。
M6 的最后一块「多币种 + 汇率」要做的是：**原币金额照原样存下来，统计仍然用本位币**。

## What Changes

- **账户带币种**：`accounts.currency`（默认 `CNY`），账户管理里可选。
- **交易记三件事**：原币金额 `originalAmountCents`、币种 `currency`、汇率 `ratePpm`（1 单位外币 = 多少本位币 × 10⁶）。
  现有的 `amountCents` **继续表示本位币金额**，所以统计、余额、净值、导出全部不受影响。
- **记一笔时**：选中的账户不是 CNY 时，出现「汇率」行（默认沿用该币种上次用过的汇率，存在 `app_state` 里）；输入框里填的是外币金额。
- **显示**：非 CNY 的账在明细与详情里显示原币金额，并在后面用小字给出折算后的本位币。
- 非目标：实时汇率（不联网）、跨币种转账、导出保留原币（导出仍写本位币金额 + `CNY`，钱数不丢，原币会丢——写进已知限制）、切换本位币。

## Capabilities

### New Capabilities

- `multi-currency`: 账户币种、外币交易的原币金额与汇率快照、按本位币统计与折合显示

### Modified Capabilities

（无：统计与余额的口径不变，仍然是"全部折成本位币"。）

## Impact

- `lib/data/db/app_database.dart`：accounts 加 `currency`，transactions 加 `currency / originalAmountCents / ratePpm`，`schemaVersion = 5`
- `lib/data/repositories/transaction_repository.dart`：`NewTransaction` 接受原币与汇率，落库时算本位币金额
- `lib/widgets/quick_entry_sheet.dart`：外币账户的汇率行
- `lib/pages/accounts_page.dart`：币种选择
- `lib/pages/transaction_detail_page.dart` / `lib/widgets/ledger_day_list.dart`：折合显示
- 测试：换算、迁移、仓储、面板、显示、设备端
