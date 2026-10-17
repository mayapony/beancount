import 'dart:convert';
import 'dart:io';

import 'package:bean_count/data/db/app_database.dart';
import 'package:bean_count/data/db/connection.dart';
import 'package:bean_count/data/db/enums.dart';
import 'package:bean_count/data/repositories/account_repository.dart';
import 'package:bean_count/data/repositories/attachment_repository.dart';
import 'package:bean_count/data/repositories/category_repository.dart';
import 'package:bean_count/data/repositories/ledger_filter.dart';
import 'package:bean_count/data/repositories/transaction_repository.dart';
import 'package:bean_count/services/import/bee_count_csv.dart';
import 'package:bean_count/services/import/import_service.dart';
import 'package:flutter_test/flutter_test.dart';

/// 性能护栏：只拦数量级退化，不做毫秒级断言（CI 机器波动大）。
///
/// 1 万笔账上跑「按月查询」与「关键词搜索」，合计超过 10 秒就说明
/// 某次改动把查询变成了 O(n²) 或引入了 N+1。
void main() {
  late AppDatabase db;
  late Directory tmp;
  late CategoryRepository categories;
  late AccountRepository accounts;
  late TransactionRepository transactions;
  late AttachmentRepository attachments;
  late ImportService importer;

  setUp(() async {
    db = AppDatabase(openInMemoryConnection());
    tmp = await Directory.systemTemp.createTemp('bean_perf');
    categories = CategoryRepository(db);
    accounts = AccountRepository(db);
    transactions = TransactionRepository(db);
    attachments = AttachmentRepository(db, directory: tmp);
    importer = ImportService(
      db: db,
      categories: categories,
      accounts: accounts,
      transactions: transactions,
      attachments: attachments,
    );
    await db.select(db.categories).get();
  });

  tearDown(() async {
    await db.close();
    if (await tmp.exists()) await tmp.delete(recursive: true);
  });

  test('万笔账本：按月查询 + 关键词搜索 < 10s', () async {
    final food = (await categories.findByName('餐饮', CategoryType.expense))!;
    final salary = (await categories.findByName('工资', CategoryType.income))!;

    final csv = StringBuffer()
      ..writeln('类型,分类,二级分类,金额,币种,账户,转出账户,转入账户,备注,时间,标签,附件');
    for (var i = 0; i < 10000; i++) {
      final day = (i % 28) + 1;
      final month = ((i ~/ 28) % 12) + 1;
      final year = 2024 + ((i ~/ 336) % 2);
      final isIncome = i % 9 == 0;
      final stamp = '$year-${month.toString().padLeft(2, '0')}-'
          '${day.toString().padLeft(2, '0')} 12:00:00';
      csv.writeln(
        '${isIncome ? '收入' : '支出'},'
        '${isIncome ? salary.name : food.name},,'
        '${isIncome ? '12000.00' : '38.50'},CNY,现金,,,'
        '记账 $i,$stamp,,',
      );
    }

    final parsed = parseBeeCountCsv(utf8.encode(csv.toString()));
    final plan = await planImport(
      service: importer,
      parsed: parsed,
      attachmentSizes: const {},
    );
    await importer.apply(plan, attachments: const {});
    expect(await transactions.count(), 10000);

    final watch = Stopwatch()..start();
    final groups = await transactions.dayGroups(year: 2025, month: 6);
    final found = await transactions.searchLedger(
      const LedgerFilter(keyword: '记账 4242'),
    );
    watch.stop();

    expect(groups, isNotEmpty);
    expect(found.matchedCount, greaterThan(0));
    // ignore: avoid_print
    print('万笔查询耗时：${watch.elapsedMilliseconds}ms');
    expect(
      watch.elapsedMilliseconds,
      lessThan(10000),
      reason: '查询从数十毫秒退化到秒级以上，通常是 N+1 或全表重扫',
    );
  });
}
