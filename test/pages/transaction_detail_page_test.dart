import 'dart:io';
import 'dart:typed_data';

import 'package:bean_count/data/db/app_database.dart';
import 'package:bean_count/data/db/connection.dart';
import 'package:bean_count/data/db/enums.dart';
import 'package:bean_count/data/repositories/account_repository.dart';
import 'package:bean_count/data/repositories/attachment_repository.dart';
import 'package:bean_count/data/repositories/category_repository.dart';
import 'package:bean_count/data/repositories/transaction_repository.dart';
import 'package:bean_count/pages/transaction_detail_page.dart';
import 'package:bean_count/theme/app_theme.dart';
import 'package:bean_count/widgets/common.dart';
import 'package:flutter/material.dart';
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
    tmp = await Directory.systemTemp.createTemp('bean_detail');
    attachments = AttachmentRepository(db, directory: tmp);
    repo = TransactionRepository(db, attachments: attachments);
    await db.select(db.transactions).get(); // 建库 + 种子
  });

  tearDown(() async {
    await db.close();
    if (await tmp.exists()) await tmp.delete(recursive: true);
  });

  Future<void> pumpDetail(WidgetTester tester, String id) async {
    final row = await repo.byId(id);
    expect(row, isNotNull, reason: '前置：交易要存在');
    await tester.pumpWidget(
      MaterialApp(
        theme: buildBeanTheme(Brightness.light),
        home: TransactionDetailPage(
          row: row!,
          repository: repo,
          attachments: attachments,
        ),
      ),
    );
    // 页面在 initState 里补标签与图片，给两帧让它落定
    await tester.pump();
    await tester.pump();
  }

  testWidgets('展示金额、分类、账户、时间、备注与标签', (tester) async {
    final account = (await accounts.all()).first;
    final created = await repo.create(
      NewTransaction(
        type: EntryType.expense,
        amountCents: 3850,
        categoryId: (await categories.findByName('餐饮', CategoryType.expense))!
            .id,
        happenedAt: DateTime(2026, 10, 17, 12, 30),
        accountId: account.id,
        note: '牛肉面',
        tags: ['出差', '报销'],
      ),
    );

    await pumpDetail(tester, created.transactionId);

    expect(find.text('-38.50'), findsOneWidget);
    expect(find.text('餐饮'), findsWidgets);
    expect(find.text(account.name), findsOneWidget);
    expect(find.text('牛肉面'), findsOneWidget);
    expect(find.text('#出差'), findsOneWidget);
    expect(find.text('#报销'), findsOneWidget);
    expect(find.textContaining('12:30'), findsOneWidget);
  });

  testWidgets('无图不出现图片区，无账户不显示账户一行', (tester) async {
    final created = await repo.create(
      NewTransaction(
        type: EntryType.expense,
        amountCents: 1200,
        categoryId: (await categories.findByName('餐饮', CategoryType.expense))!
            .id,
        happenedAt: DateTime(2026, 10, 17, 8),
      ),
    );

    await pumpDetail(tester, created.transactionId);

    expect(find.byType(Image), findsNothing);
    expect(find.text('账户'), findsNothing);
    expect(find.text('备注'), findsNothing);
  });

  testWidgets('有图时显示缩略图，数量写进标题', (tester) async {
    final created = await repo.create(
      NewTransaction(
        type: EntryType.expense,
        amountCents: 9900,
        categoryId: (await categories.findByName('购物', CategoryType.expense))!
            .id,
        happenedAt: DateTime(2026, 10, 17, 15),
        note: '带两张图',
      ),
    );
    await tester.runAsync(() async {
      await attachments.ensureReady();
      // 两张极小的 PNG，内容不重要，能落盘即可
      final bytes = Uint8List.fromList(<int>[0x89, 0x50, 0x4E, 0x47, 0, 0, 0, 0]);
      await attachments.add(
        transactionId: created.transactionId,
        bytes: bytes,
        fileName: 'a.png',
      );
      await attachments.add(
        transactionId: created.transactionId,
        bytes: Uint8List.fromList(<int>[0x89, 0x50, 0x4E, 0x48, 0, 0, 0, 0]),
        fileName: 'b.png',
        sortOrder: 1,
      );
    });

    await pumpDetail(tester, created.transactionId);

    expect(find.text('图片 · 2'), findsOneWidget);
    // 坏图会落到 errorBuilder 里的图标，但容器还在
    expect(find.byType(ClipRRect), findsWidgets);
  });

  testWidgets('空图片列表不渲染「图片 ·」标题', (tester) async {
    final created = await repo.create(
      NewTransaction(
        type: EntryType.income,
        amountCents: 500000,
        categoryId: (await categories.findByName('工资', CategoryType.income))!.id,
        happenedAt: DateTime(2026, 10, 10, 9),
        note: '发工资',
      ),
    );

    await pumpDetail(tester, created.transactionId);

    expect(find.textContaining('图片 ·'), findsNothing);
    expect(find.text('+5,000.00'), findsOneWidget);
    expect(find.text('收入'), findsOneWidget);
    expect(find.byType(BeanCard), findsWidgets);
  });
}
