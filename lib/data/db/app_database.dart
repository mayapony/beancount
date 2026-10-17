import 'package:drift/drift.dart';

import '../seed.dart';
import 'enums.dart';

part 'app_database.g.dart';

/// 分类：最多两级，`parentId` 为空表示一级。
///
/// 主键用 TEXT id（种子用 `cat-food` 这类可读 id），
/// 这样导入时按「同名同类型」复用分类不需要再回查自增号。
@TableIndex(name: 'idx_categories_type_sort', columns: {#type, #sortOrder})
class Categories extends Table {
  TextColumn get id => text()();
  TextColumn get name => text()();
  TextColumn get type => textEnum<CategoryType>()();
  TextColumn get parentId => text().nullable().references(Categories, #id)();

  /// ARGB 颜色值，`0xFFF59E0B` 这类。
  IntColumn get color => integer()();

  /// 图标标识，映射到 `kCategoryIcons` 的 key。
  TextColumn get icon => text()();
  IntColumn get sortOrder => integer().withDefault(const Constant(0))();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column> get primaryKey => {id};
}

/// 账户：余额不落库，一律由 `initialBalanceCents` + 关联交易推导。
@TableIndex(name: 'idx_accounts_sort', columns: {#sortOrder})
class Accounts extends Table {
  TextColumn get id => text()();
  TextColumn get name => text()();
  TextColumn get type =>
      textEnum<AccountType>().withDefault(const Constant('wallet'))();
  IntColumn get initialBalanceCents =>
      integer().withDefault(const Constant(0))();
  IntColumn get sortOrder => integer().withDefault(const Constant(0))();

  /// 信用卡账单日 / 还款日（1–28）。只对 `type == credit` 有意义；
  /// 限定到 28 是为了避开大小月与 2 月的漂移——提醒不需要精确到 31 号。
  IntColumn get billingDay => integer().nullable()();
  IntColumn get dueDay => integer().nullable()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column> get primaryKey => {id};
}

/// 标签：名称唯一，可自由创建。
class Tags extends Table {
  TextColumn get id => text()();
  TextColumn get name => text().unique()();
  IntColumn get color => integer().nullable()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column> get primaryKey => {id};
}

/// 交易：金额一律存整数分；`dedupeKey` 唯一，保证导入幂等。
///
/// `categoryId` 可空：转账没有分类。`toAccountId` 只在转账时有值——
/// 记成「一条记录 + 两端账户」而不是两条腿，统计与删除才只有一处逻辑。
@TableIndex(name: 'idx_transactions_happened_at', columns: {#happenedAt})
@TableIndex(name: 'idx_transactions_category', columns: {#categoryId})
class Transactions extends Table {
  TextColumn get id => text()();
  TextColumn get type => textEnum<EntryType>()();
  IntColumn get amountCents => integer()();
  TextColumn get categoryId =>
      text().nullable().references(Categories, #id)();
  TextColumn get accountId =>
      text().nullable().references(Accounts, #id)();

  /// 转入账户：仅 `type == transfer` 时非空。
  TextColumn get toAccountId =>
      text().nullable().references(Accounts, #id)();

  /// 由循环规则生成时：规则 id 与期数（`yyyy-MM`）。
  ///
  /// 两个字段一起构成"这一期已经补过"的判据——比只靠去重键更稳：
  /// 用户把自动生成的交易改过金额/备注后，键会变，但期数标记还在。
  TextColumn get recurringRuleId =>
      text().nullable().references(RecurringRules, #id)();
  TextColumn get recurringPeriod => text().nullable()();

  /// 规范化后的备注（trim 过、空串而不是 null），参与去重键计算。
  TextColumn get note => text().withDefault(const Constant(''))();
  DateTimeColumn get happenedAt => dateTime()();
  TextColumn get dedupeKey => text().unique()();
  TextColumn get source =>
      textEnum<EntrySource>().withDefault(const Constant('manual'))();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column> get primaryKey => {id};
}

/// 交易 ↔ 标签，多对多。
class TransactionTags extends Table {
  TextColumn get transactionId =>
      text().references(Transactions, #id, onDelete: KeyAction.cascade)();
  TextColumn get tagId => text().references(Tags, #id, onDelete: KeyAction.cascade)();

  @override
  Set<Column> get primaryKey => {transactionId, tagId};
}

/// 记账凭证图片：文件在 `<appDocs>/attachments/`，这里只存文件名与元信息。
///
/// `fileName` **不唯一**：真实导出里存在两笔交易共用同一张截图的情况，
/// 文件只存一份，删除时按引用计数回收。
@TableIndex(name: 'idx_attachments_tx', columns: {#transactionId})
@TableIndex(name: 'idx_attachments_file', columns: {#fileName})
class Attachments extends Table {
  TextColumn get id => text()();
  TextColumn get transactionId =>
      text().references(Transactions, #id, onDelete: KeyAction.cascade)();
  TextColumn get fileName => text()();
  TextColumn get originalName => text().nullable()();
  IntColumn get fileSize => integer().withDefault(const Constant(0))();
  IntColumn get sortOrder => integer().withDefault(const Constant(0))();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column> get primaryKey => {id};
}

/// 循环记账规则：每月固定日自动补记一笔（支出/收入/转账）。
///
/// 不存「上次执行到哪」——补记是否已发生由交易的去重键（带 rule+期数的 salt）判定，
/// 少一个会漂移的状态字段，也就少一类"补重了/补漏了"的 bug。
class RecurringRules extends Table {
  TextColumn get id => text()();
  TextColumn get type => textEnum<EntryType>()();
  IntColumn get amountCents => integer()();
  TextColumn get categoryId =>
      text().nullable().references(Categories, #id)();
  TextColumn get accountId =>
      text().nullable().references(Accounts, #id)();
  TextColumn get toAccountId =>
      text().nullable().references(Accounts, #id)();
  TextColumn get note => text().withDefault(const Constant(''))();

  /// 1..31：超过当月天数时落到该月最后一天（31 即「月末」）。
  IntColumn get dayOfMonth => integer()();

  /// 生效起始月：补记不会早于这个月。
  IntColumn get startYear => integer()();
  IntColumn get startMonth => integer()();
  BoolColumn get enabled => boolean().withDefault(const Constant(true))();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column> get primaryKey => {id};
}

/// 轻量键值：上次记账的选择等。
class AppState extends Table {
  TextColumn get key => text()();
  TextColumn get value => text()();

  @override
  Set<Column> get primaryKey => {key};
}

@DriftDatabase(
  tables: [
    Categories,
    Accounts,
    Tags,
    Transactions,
    TransactionTags,
    Attachments,
    AppState,
    RecurringRules,
  ],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase(super.e);

  @override
  int get schemaVersion => 4;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (m) async {
          await m.createAll();
          // 首次建库即写入种子（12 支出分类 + 6 收入分类 + 1 默认账户）。
          // 幂等：固定 id + insertOrIgnore，重复执行不产生重复行。
          await seedDefaults(this);
        },
        onUpgrade: (m, from, to) async {
          if (from < 2) {
            // v2：转账。分类放宽为可空 + 新增转入账户，SQLite 只能重建表。
            await m.alterTable(
              TableMigration(
                transactions,
                newColumns: [transactions.toAccountId],
              ),
            );
            // 重建表后把索引补回来（drift 的 creating 只重建表本身）
            await customStatement(
              'CREATE INDEX IF NOT EXISTS idx_transactions_happened_at '
              'ON transactions (happened_at)',
            );
            await customStatement(
              'CREATE INDEX IF NOT EXISTS idx_transactions_category '
              'ON transactions (category_id)',
            );
          }
          if (from < 3) {
            // v3：循环记账规则；交易上记录「由哪条规则、哪一期」生成。
            await m.createTable(recurringRules);
            await m.alterTable(
              TableMigration(
                transactions,
                newColumns: [
                  transactions.recurringRuleId,
                  transactions.recurringPeriod,
                ],
              ),
            );
            await customStatement(
              'CREATE INDEX IF NOT EXISTS idx_transactions_happened_at '
              'ON transactions (happened_at)',
            );
            await customStatement(
              'CREATE INDEX IF NOT EXISTS idx_transactions_category '
              'ON transactions (category_id)',
            );
          }
          if (from < 4) {
            // v4：信用卡的账单日 / 还款日（可空，老数据不动）
            await m.alterTable(
              TableMigration(
                accounts,
                newColumns: [accounts.billingDay, accounts.dueDay],
              ),
            );
          }
        },
        beforeOpen: (details) async {
          await customStatement('PRAGMA foreign_keys = ON');
        },
      );
}
