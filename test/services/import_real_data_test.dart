import 'dart:convert';
import 'dart:io';

import 'package:bean_count/data/db/app_database.dart';
import 'package:bean_count/data/db/connection.dart';
import 'package:bean_count/data/repositories/account_repository.dart';
import 'package:bean_count/data/repositories/attachment_repository.dart';
import 'package:bean_count/data/repositories/category_repository.dart';
import 'package:bean_count/data/repositories/transaction_repository.dart';
import 'package:bean_count/services/import/bee_count_csv.dart';
import 'package:bean_count/services/import/import_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late AppDatabase db;
  late Directory tmp;
  late ImportService service;
  late TransactionRepository transactions;

  setUp(() async {
    db = AppDatabase(openInMemoryConnection());
    tmp = await Directory.systemTemp.createTemp('bean_real_import');
    final categories = CategoryRepository(db);
    final accounts = AccountRepository(db);
    transactions = TransactionRepository(db);
    service = ImportService(
      db: db,
      categories: categories,
      accounts: accounts,
      transactions: transactions,
      attachments: AttachmentRepository(db, directory: tmp),
    );
    await db.select(db.transactions).get();
  });

  tearDown(() async {
    await db.close();
    if (await tmp.exists()) await tmp.delete(recursive: true);
  });

  test('真实导出：总行数 = 可导入 + 跳过，且数字可复算', () async {
    final file = File('test/fixtures/local/beecount_real.csv');
    if (!file.existsSync()) {
      // 真实账本只在本地存在（gitignore），CI 上没有就跳过
      // ignore: avoid_print
      print('跳过：test/fixtures/local/beecount_real.csv 不存在');
      return;
    }

    final parsed = parseBeeCountCsv(file.readAsBytesSync());
    expect(parsed.ok, isTrue, reason: parsed.fatal);

    final plan = await planImport(
      service: service,
      parsed: parsed,
      attachmentSizes: const {},
    );

    expect(
      plan.importable + plan.skippedCount,
      plan.totalRows,
      reason: '可导入 + 跳过 必须等于总行数',
    );
    expect(plan.totalRows, 48);
    expect(plan.importable, 48, reason: '这批没有转账行');

    final report = await service.apply(plan, attachments: const {});
    expect(report.inserted, 48);
    expect(report.failed, 0);
    expect(await transactions.count(), 48);

    // 真实数据里的分类名与账户名都进库了
    final accounts = await AccountRepository(db).all();
    expect(
      accounts.map((a) => a.name),
      containsAll(['支付宝', '微信', '招商银行']),
    );
    final categories = await CategoryRepository(db).allCategories();
    expect(
      categories.map((c) => c.name),
      containsAll(['餐饮', '零食', '外卖', '工资']),
    );
  });

  test('1 万行性能：解析 + 计划 + 写入在可接受时间内', () async {
    final buffer = StringBuffer('类型,分类,金额,时间,备注\n');
    for (var i = 0; i < 10000; i++) {
      final day = (1 + (i % 28)).toString().padLeft(2, '0');
      final minute = (i % 60).toString().padLeft(2, '0');
      buffer.writeln(
        '支出,餐饮,${(i % 500) + 1}.50,  2026-09-$day 08:$minute:00  ,row$i',
      );
    }
    final bytes = utf8.encode(buffer.toString());

    final watch = Stopwatch()..start();
    final parsed = parseBeeCountCsv(bytes);
    expect(parsed.rows, hasLength(10000));

    final plan = await planImport(
      service: service,
      parsed: parsed,
      attachmentSizes: const {},
    );
    final report = await service.apply(plan, attachments: const {});
    watch.stop();

    expect(report.inserted, 10000);
    expect(report.failed, 0);
    // Debug 下给 20s 余量；真机 Release 一般在 2–4s
    expect(
      watch.elapsed.inSeconds,
      lessThan(20),
      reason: '1 万行用了 ${watch.elapsed.inMilliseconds}ms',
    );
    // ignore: avoid_print
    print('1 万行耗时：${watch.elapsed.inMilliseconds}ms');
  }, timeout: const Timeout(Duration(minutes: 3)));
}
