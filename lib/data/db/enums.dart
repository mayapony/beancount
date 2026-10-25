/// 数据层使用的枚举。
///
/// drift 的 `textEnum` 会把枚举名写进 TEXT 列（`expense` / `income`），
/// 因此这里枚举的**名字**就是磁盘格式，改名等于改 schema。
library;

/// 一笔交易的收支方向。
///
/// `transfer` 是账户之间的资金移动：没有分类，两端账户都必填，
/// 且不计入收入/支出统计。
enum EntryType { expense, income, transfer }

/// 分类所属的收支类型（与 [EntryType] 同形，但语义上独立：
/// 分类的归属不会因为交易方向扩展而变化）。
enum CategoryType { expense, income }

/// 账户类型，仅用于展示与图标选择，不参与余额计算。
enum AccountType { wallet, debit, credit, other }

/// 交易的来源，用来区分手工记账、导入与自动记账（无障碍 / 通知 / 截图）。
enum EntrySource { manual, import, auto }
