import 'dart:convert';
import 'dart:io';

import 'package:bean_count/data/db/app_database.dart';
import 'package:bean_count/data/db/connection.dart';
import 'package:bean_count/data/db/enums.dart';
import 'package:bean_count/data/repositories/account_repository.dart';
import 'package:bean_count/data/repositories/attachment_repository.dart';
import 'package:bean_count/data/repositories/category_repository.dart';
import 'package:bean_count/data/repositories/transaction_repository.dart';
import 'package:bean_count/services/import/bee_count_archive.dart';
import 'package:bean_count/services/import/bee_count_csv.dart';
import 'package:bean_count/services/import/import_models.dart';
import 'package:bean_count/services/import/import_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late AppDatabase db;
  late Directory tmp;
  late CategoryRepository categories;
  late AccountRepository accounts;
  late TransactionRepository transactions;
  late AttachmentRepository attachments;
  late ImportService service;

  setUp(() async {
    db = AppDatabase(openInMemoryConnection());
    tmp = await Directory.systemTemp.createTemp('bean_import');
    categories = CategoryRepository(db);
    accounts = AccountRepository(db);
    transactions = TransactionRepository(db);
    attachments = AttachmentRepository(db, directory: tmp);
    service = ImportService(
      db: db,
      categories: categories,
      accounts: accounts,
      transactions: transactions,
      attachments: attachments,
    );
    await db.select(db.transactions).get(); // 建库 + 种子
  });

  tearDown(() async {
    await db.close();
    if (await tmp.exists()) await tmp.delete(recursive: true);
  });

  ParseResult parsed() => parseBeeCountCsv(
        File('test/fixtures/beecount_sample.csv').readAsBytesSync(),
      );

  Map<String, ExtractedAttachment> onlyFirstAttachment() => {
        'sha_aaaa1111.jpg': ExtractedAttachment(
          fileName: 'sha_aaaa1111.jpg',
          bytes: utf8.encode('fake-jpeg'),
          originalName: 'Screenshot_a.jpg',
        ),
      };

  test('计划：9 行可导入、1 行转账跳过、新账户与标签列清楚', () async {
    final result = parsed();
    final plan = await planImport(
      service: service,
      parsed: result,
      attachmentSizes: {'sha_aaaa1111.jpg': 9},
    );

    expect(plan.totalRows, 10);
    expect(plan.importable, 9);
    expect(plan.skippedCount, 1);
    expect(plan.skipped.single.reason, '转账暂不支持');

    // 种子已含餐饮/交通/购物/工资，不该被算成新建
    expect(plan.newCategories, isEmpty);
    expect(plan.newAccounts, containsAll(['现金', '储蓄卡', '信用卡']));
    expect(plan.newTags, containsAll(['图片记账', 'AI记账', '通勤']));

    // 只有第一张图在包里；其余记 warning 而不是让整行失败
    expect(plan.attachmentFiles, ['sha_aaaa1111.jpg']);
    expect(
      plan.attachmentWarnings.where((w) => w.contains('缺少附件')),
      isNotEmpty,
    );
  });

  test('执行：写入 9 笔、附件落盘、报告数字对得上', () async {
    final plan = await planImport(
      service: service,
      parsed: parsed(),
      attachmentSizes: {'sha_aaaa1111.jpg': 9},
    );
    final report = await service.apply(
      plan,
      attachments: onlyFirstAttachment(),
    );

    expect(report.inserted, 9);
    expect(report.skipped, 1);
    expect(report.failed, 0);
    expect(report.attachmentsSaved, 1);
    expect(report.attachmentsMissing, 4, reason: 'bbbb + cccc + 两张 dddd');
    expect(report.newAccounts, 3);
    expect(await transactions.count(), 9);

    // 账户真的建出来了，且初始余额为 0
    final accountNames = (await accounts.all()).map((a) => a.name).toSet();
    expect(accountNames, containsAll(['现金', '储蓄卡', '信用卡']));
    for (final a in await accounts.all()) {
      expect(a.initialBalanceCents, 0);
    }

    // 附件文件落在目录里
    expect(tmp.listSync().whereType<File>(), hasLength(1));

    // 报告文本可复制，且包含关键数字
    final text = report.toText();
    expect(text, contains('成功：9'));
    expect(text, contains('跳过：1'));
    expect(text, contains('附件：写入 1 张，缺失 4 张'));
  });

  test('幂等：同一份文件再导一次，新增 0', () async {
    final first = await planImport(
      service: service,
      parsed: parsed(),
      attachmentSizes: const {},
    );
    await service.apply(first, attachments: const {});

    final second = await planImport(
      service: service,
      parsed: parsed(),
      attachmentSizes: const {},
    );
    expect(second.importable, 0);
    expect(second.skippedCount, 10, reason: '9 条已存在 + 1 条转账');

    final report = await service.apply(second, attachments: const {});
    expect(report.inserted, 0);
    expect(await transactions.count(), 9);
  });

  test('库里已有同时间去重键时，计划阶段就跳过', () async {
    final rows = parsed().rows;
    final first = rows.first;
    final food = (await categories.findByName('餐饮', CategoryType.expense))!;
    await transactions.create(
      NewTransaction(
        type: first.type,
        amountCents: first.amountCents,
        categoryId: food.id,
        happenedAt: first.happenedAt,
        note: first.note,
      ),
    );

    final plan = await planImport(
      service: service,
      parsed: parsed(),
      attachmentSizes: const {},
    );

    expect(plan.importable, 8);
    expect(
      plan.skipped.where((s) => s.reason.contains('已存在')),
      hasLength(1),
    );
  });

  test('二级分类：父分类先建、子分类挂在父下', () async {
    const csv = '类型,分类,二级分类,金额,时间\n'
        '支出,餐饮,午餐,18.00,  2026-10-17 12:30:00  \n'
        '支出,餐饮,晚餐,22.00,  2026-10-17 19:30:00  \n';
    final plan = await planImport(
      service: service,
      parsed: parseBeeCountCsv(utf8.encode(csv)),
      attachmentSizes: const {},
    );

    expect(plan.newCategories.map((c) => c.display), containsAll(['餐饮 / 午餐', '餐饮 / 晚餐']));

    final report = await service.apply(plan, attachments: const {});
    expect(report.inserted, 2);

    final food = await categories.findByName('餐饮', CategoryType.expense);
    final lunch = await categories.findByName(
      '午餐',
      CategoryType.expense,
      parentId: food!.id,
    );
    expect(lunch, isNotNull);
    expect(lunch!.parentId, food.id);
    expect(report.failed, 0);
  });
}
