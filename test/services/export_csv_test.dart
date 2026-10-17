import 'dart:convert';
import 'dart:io';

import 'package:bean_count/data/db/app_database.dart';
import 'package:bean_count/data/db/connection.dart';
import 'package:bean_count/data/db/enums.dart';
import 'package:bean_count/data/repositories/account_repository.dart';
import 'package:bean_count/data/repositories/attachment_repository.dart';
import 'package:bean_count/data/repositories/category_repository.dart';
import 'package:bean_count/data/repositories/transaction_repository.dart';
import 'package:bean_count/services/export/bee_count_csv_writer.dart';
import 'package:bean_count/services/import/bee_count_csv.dart';
import 'package:csv/csv.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late AppDatabase db;
  late TransactionRepository repo;
  late CategoryRepository categories;
  late AccountRepository accounts;
  late AttachmentRepository attachments;
  late Directory tmp;

  setUp(() async {
    db = AppDatabase(openInMemoryConnection());
    categories = CategoryRepository(db);
    accounts = AccountRepository(db);
    tmp = await Directory.systemTemp.createTemp('bean_csv_export');
    attachments = AttachmentRepository(db, directory: tmp);
    repo = TransactionRepository(db, attachments: attachments);
    await db.select(db.transactions).get();
  });

  tearDown(() async {
    await db.close();
    if (await tmp.exists()) await tmp.delete(recursive: true);
  });

  String textOf(List<int> bytes) =>
      utf8.decode(bytes.skip(3).toList()); // 跳过 BOM

  test('表头与列序与导入端一致', () {
    final csv = buildBeeCountCsv(const []);
    expect(csv.sublist(0, 3), [0xEF, 0xBB, 0xBF], reason: '带 BOM');

    final lines = textOf(csv).trimRight().split('\n');
    expect(lines, hasLength(1), reason: '空账本只有表头');
    expect(lines.single, kBeeCountExportHeader.join(','));
  });

  test('单行取值：金额两位小数、时间格式、标签与附件逗号分隔', () async {
    final account = (await accounts.all()).first;
    final category = (await categories.findByName('餐饮', CategoryType.expense))!;
    final created = await repo.create(
      NewTransaction(
        type: EntryType.expense,
        amountCents: 3850,
        categoryId: category.id,
        happenedAt: DateTime(2026, 10, 17, 9, 5, 7),
        accountId: account.id,
        note: '牛肉面,加蛋',
        tags: ['出差', '报销'],
      ),
    );
    await attachments.ensureReady();
    await attachments.add(
      transactionId: created.transactionId,
      bytes: const [1, 2, 3],
      fileName: 'a.png',
    );

    final rows = await repo.exportRows();
    final csv = buildBeeCountCsv(rows);
    final parsed = const CsvToListConverter(shouldParseNumbers: false, eol: '\n').convert(textOf(csv));

    expect(parsed.first, kBeeCountExportHeader);
    final cells = parsed[1];
    expect(cells[0], '支出');
    expect(cells[1], '餐饮');
    expect(cells[2], '', reason: '没有二级分类');
    expect(cells[3], '38.50');
    expect(cells[4], 'CNY');
    expect(cells[5], account.name);
    expect(cells[8], '牛肉面,加蛋', reason: '含逗号的备注要被引号包住且还原');
    expect(cells[9], '2026-10-17 09:05:07');
    expect(cells[10], '出差,报销');
    expect(cells[11], 'a.png');
  });

  test('往返：写出的 CSV 能被导入解析器读回同样的账', () async {
    final account = (await accounts.all()).first;
    final parent = (await categories.findByName('餐饮', CategoryType.expense))!;
    final child = await categories.ensure(
      name: '外卖',
      type: CategoryType.expense,
      parentId: parent.id,
    );
    await repo.create(
      NewTransaction(
        type: EntryType.expense,
        amountCents: 3850,
        categoryId: child.id,
        happenedAt: DateTime(2026, 10, 17, 12, 30),
        accountId: account.id,
        note: '麻辣烫',
        tags: ['家庭'],
      ),
    );
    await repo.create(
      NewTransaction(
        type: EntryType.income,
        amountCents: 1451901,
        categoryId: (await categories.findByName('工资', CategoryType.income))!.id,
        happenedAt: DateTime(2026, 10, 16, 10),
        note: '',
      ),
    );

    final csv = buildBeeCountCsv(await repo.exportRows());
    final result = parseBeeCountCsv(csv);

    expect(result.fatal, isNull);
    expect(result.rows, hasLength(2));
    expect(result.skipped, isEmpty);

    // exportRows 按时间升序：10-16 的工资在前，10-17 的支出在后
    final expense = result.rows.last;
    expect(expense.type, EntryType.expense);
    expect(expense.categoryName, '餐饮');
    expect(expense.subcategoryName, '外卖');
    expect(expense.amountCents, 3850);
    expect(expense.accountName, account.name);
    expect(expense.note, '麻辣烫');
    expect(expense.tags, ['家庭']);
    expect(expense.happenedAt, DateTime(2026, 10, 17, 12, 30));

    final income = result.rows.first;
    expect(income.type, EntryType.income);
    expect(income.amountCents, 1451901);
    expect(income.categoryName, '工资');
    expect(income.note, '');
  });

  test('无标签无附件的行两列为空字符串', () async {
    await repo.create(
      NewTransaction(
        type: EntryType.expense,
        amountCents: 100,
        categoryId: (await categories.findByName('餐饮', CategoryType.expense))!
            .id,
        happenedAt: DateTime(2026, 10, 17, 8),
      ),
    );

    final parsed = const CsvToListConverter(shouldParseNumbers: false, eol: '\n')
        .convert(textOf(buildBeeCountCsv(await repo.exportRows())));
    final cells = parsed[1];
    expect(cells[10], '');
    expect(cells[11], '');
    expect(cells.length, kBeeCountExportHeader.length);
  });

  test('金额格式化不经过浮点', () {
    expect(formatCents(3850), '38.50');
    expect(formatCents(5), '0.05');
    expect(formatCents(1451901), '14519.01');
    expect(formatCents(100), '1.00');
  });
}
