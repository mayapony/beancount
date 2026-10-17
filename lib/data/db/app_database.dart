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
@TableIndex(name: 'idx_transactions_happened_at', columns: {#happenedAt})
@TableIndex(name: 'idx_transactions_category', columns: {#categoryId})
class Transactions extends Table {
  TextColumn get id => text()();
  TextColumn get type => textEnum<EntryType>()();
  IntColumn get amountCents => integer()();
  TextColumn get categoryId => text().references(Categories, #id)();
  TextColumn get accountId =>
      text().nullable().references(Accounts, #id)();

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
  ],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase(super.e);

  @override
  int get schemaVersion => 1;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (m) async {
          await m.createAll();
          // 首次建库即写入种子（12 支出分类 + 6 收入分类 + 1 默认账户）。
          // 幂等：固定 id + insertOrIgnore，重复执行不产生重复行。
          await seedDefaults(this);
        },
        onUpgrade: (m, from, to) async {
          // 目前只有 v1；后续升级必须以迁移步进的形式追加，禁止清表。
        },
        beforeOpen: (details) async {
          await customStatement('PRAGMA foreign_keys = ON');
        },
      );
}
