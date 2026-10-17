import 'dart:io';

import 'package:bean_count/data/db/app_database.dart';
import 'package:bean_count/data/db/connection.dart';
import 'package:bean_count/data/db/enums.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('内存库可打开并建表', () async {
    final db = AppDatabase(openInMemoryConnection());
    addTearDown(db.close);

    // 七张表都能查询即说明 onCreate 的 createAll 生效；
    // 分类与账户在首次建库时被种子填充（12+6 与 1 个默认账户）。
    expect(await db.select(db.categories).get(), hasLength(18));
    expect(await db.select(db.accounts).get(), hasLength(1));
    expect(await db.select(db.tags).get(), isEmpty);
    expect(await db.select(db.transactions).get(), isEmpty);
    expect(await db.select(db.transactionTags).get(), isEmpty);
    expect(await db.select(db.attachments).get(), isEmpty);
    expect(await db.select(db.appState).get(), isEmpty);
  });

  test('文件库重开后数据仍在', () async {
    final dir = await Directory.systemTemp.createTemp('bean_count_db_test');
    addTearDown(() => dir.delete(recursive: true));
    final file = File('${dir.path}/bean_count.sqlite');

    final first = AppDatabase(NativeDatabase(file));
    await first
        .into(first.appState)
        .insert(AppStateCompanion.insert(key: 'last_type', value: 'expense'));
    await first.close();

    final second = AppDatabase(NativeDatabase(file));
    addTearDown(second.close);
    final rows = await second.select(second.appState).get();
    expect(rows.single.value, 'expense');
  });

  test('外键约束在打开时生效', () async {
    final db = AppDatabase(openInMemoryConnection());
    addTearDown(db.close);

    await expectLater(
      db.into(db.transactions).insert(
            TransactionsCompanion.insert(
              id: 'tx-bad',
              type: EntryType.expense,
              amountCents: 100,
              categoryId: 'cat-does-not-exist',
              happenedAt: DateTime(2026, 10, 17, 12),
              dedupeKey: 'deadbeef',
            ),
          ),
      throwsA(isA<SqliteException>()),
    );
  });
}
