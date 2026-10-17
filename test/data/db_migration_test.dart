import 'dart:io';

import 'package:bean_count/data/db/app_database.dart';
import 'package:bean_count/data/db/enums.dart';
import 'package:drift/drift.dart' hide isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

/// v1 → v2 迁移：转账上线时 `category_id` 放宽为可空并新增 `to_account_id`。
///
/// 这里不是"跑一下看看"：先用 v1 的真实 DDL 造一个老库（含数据与索引），
/// 再用新代码打开，验证历史数据一个字段都没变、索引还在、迁移后能写转账。
void main() {
  late Directory tmp;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('bean_migration');
  });

  tearDown(() async {
    if (await tmp.exists()) await tmp.delete(recursive: true);
  });

  /// v1 的表结构（transactions 的 category_id 是 NOT NULL，且没有 to_account_id）。
  void createV1Schema(Object raw) {
    final db = raw as dynamic;
    db.execute('''
      CREATE TABLE categories (
        id TEXT NOT NULL PRIMARY KEY,
        name TEXT NOT NULL,
        type TEXT NOT NULL,
        parent_id TEXT NULL REFERENCES categories (id),
        color INTEGER NOT NULL,
        icon TEXT NOT NULL,
        sort_order INTEGER NOT NULL DEFAULT 0,
        created_at INTEGER NOT NULL
      )
    ''');
    db.execute('''
      CREATE TABLE accounts (
        id TEXT NOT NULL PRIMARY KEY,
        name TEXT NOT NULL,
        type TEXT NOT NULL DEFAULT 'wallet',
        initial_balance_cents INTEGER NOT NULL DEFAULT 0,
        sort_order INTEGER NOT NULL DEFAULT 0,
        created_at INTEGER NOT NULL
      )
    ''');
    db.execute('''
      CREATE TABLE transactions (
        id TEXT NOT NULL PRIMARY KEY,
        type TEXT NOT NULL,
        amount_cents INTEGER NOT NULL,
        category_id TEXT NOT NULL REFERENCES categories (id),
        account_id TEXT NULL REFERENCES accounts (id),
        note TEXT NOT NULL DEFAULT '',
        happened_at INTEGER NOT NULL,
        dedupe_key TEXT NOT NULL UNIQUE,
        source TEXT NOT NULL DEFAULT 'manual',
        created_at INTEGER NOT NULL
      )
    ''');
    db.execute(
      'CREATE INDEX idx_transactions_happened_at ON transactions (happened_at)',
    );
    db.execute(
      'CREATE INDEX idx_transactions_category ON transactions (category_id)',
    );
    db.execute('''
      CREATE TABLE tags (
        id TEXT NOT NULL PRIMARY KEY,
        name TEXT NOT NULL UNIQUE,
        color INTEGER NULL,
        created_at INTEGER NOT NULL
      )
    ''');
    db.execute('''
      CREATE TABLE transaction_tags (
        transaction_id TEXT NOT NULL REFERENCES transactions (id) ON DELETE CASCADE,
        tag_id TEXT NOT NULL REFERENCES tags (id) ON DELETE CASCADE,
        PRIMARY KEY (transaction_id, tag_id)
      )
    ''');
    db.execute('''
      CREATE TABLE attachments (
        id TEXT NOT NULL PRIMARY KEY,
        transaction_id TEXT NOT NULL REFERENCES transactions (id) ON DELETE CASCADE,
        file_name TEXT NOT NULL,
        original_name TEXT NULL,
        file_size INTEGER NOT NULL DEFAULT 0,
        sort_order INTEGER NOT NULL DEFAULT 0,
        created_at INTEGER NOT NULL
      )
    ''');
    db.execute('''
      CREATE TABLE app_state (
        key TEXT NOT NULL PRIMARY KEY,
        value TEXT NOT NULL
      )
    ''');

    // 历史数据：一个分类、两个账户、一笔支出
    db.execute(
      "INSERT INTO categories (id, name, type, color, icon, sort_order, created_at) "
      "VALUES ('cat-food', '餐饮', 'expense', 4294967295, 'restaurant', 0, 0)",
    );
    db.execute(
      "INSERT INTO accounts (id, name, type, initial_balance_cents, sort_order, created_at) "
      "VALUES ('acc-a', '支付宝', 'wallet', 0, 0, 0)",
    );
    db.execute(
      "INSERT INTO accounts (id, name, type, initial_balance_cents, sort_order, created_at) "
      "VALUES ('acc-b', '招商银行卡', 'debit', 0, 1, 0)",
    );
    db.execute(
      'INSERT INTO transactions '
      '(id, type, amount_cents, category_id, account_id, note, happened_at, '
      'dedupe_key, source, created_at) '
      "VALUES ('tx-old', 'expense', 3850, 'cat-food', 'acc-a', '牛肉面', 1760000000, "
      "'deadbeefdeadbeef', 'manual', 0)",
    );
  }

  test('v1 库升级到 v2：历史数据不变、索引还在、能写转账', () async {
    final file = File('${tmp.path}/v1.sqlite');
    final executor = NativeDatabase(
      file,
      setup: (raw) {
        createV1Schema(raw);
        raw.execute('PRAGMA user_version = 1');
      },
    );

    final db = AppDatabase(executor);
    final rows = await db.select(db.transactions).get();

    // 历史交易一个字段都没变
    expect(rows, hasLength(1));
    final old = rows.single;
    expect(old.id, 'tx-old');
    expect(old.amountCents, 3850);
    expect(old.categoryId, 'cat-food');
    expect(old.accountId, 'acc-a');
    expect(old.note, '牛肉面');
    expect(old.dedupeKey, 'deadbeefdeadbeef');
    expect(old.type, EntryType.expense);
    expect(old.toAccountId, isNull);

    // 索引仍在（重建表最容易丢的就是它们）
    final indexes = await db.customSelect(
      "SELECT name FROM sqlite_master WHERE type = 'index' "
      "AND tbl_name = 'transactions'",
    ).get();
    final names = indexes.map((r) => r.read<String>('name')).toSet();
    expect(names, contains('idx_transactions_happened_at'));
    expect(names, contains('idx_transactions_category'));

    // 版本号推进到 2
    final version = await db.customSelect('PRAGMA user_version').getSingle();
    expect(version.data.values.first, 2);

    // 迁移后能写转账：分类为空、两端账户俱在
    await db.into(db.transactions).insert(
          TransactionsCompanion.insert(
            id: 'tx-transfer',
            type: EntryType.transfer,
            amountCents: 50000,
            categoryId: const Value(null),
            accountId: const Value('acc-b'),
            toAccountId: const Value('acc-a'),
            happenedAt: DateTime(2026, 10, 18, 12),
            dedupeKey: 'newkeynewkey0001',
          ),
        );
    final transfer = await (db.select(db.transactions)
          ..where((t) => t.id.equals('tx-transfer')))
        .getSingle();
    expect(transfer.categoryId, isNull);
    expect(transfer.toAccountId, 'acc-a');

    await db.close();
  });

  test('全新库直接建成 v2，不需要迁移', () async {
    final file = File('${tmp.path}/fresh.sqlite');
    final db = AppDatabase(NativeDatabase(file));
    await db.select(db.transactions).get();

    final columns = await db.customSelect(
      "SELECT name FROM pragma_table_info('transactions')",
    ).get();
    final names = columns.map((r) => r.read<String>('name')).toSet();
    expect(names, contains('to_account_id'));
    expect(names, contains('category_id'));

    final version = await db.customSelect('PRAGMA user_version').getSingle();
    expect(version.data.values.first, 2);
    await db.close();
  });
}
