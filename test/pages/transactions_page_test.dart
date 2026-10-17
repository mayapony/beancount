import 'package:bean_count/data/db/app_database.dart';
import 'package:bean_count/data/db/connection.dart';
import 'package:bean_count/data/db/enums.dart';
import 'package:bean_count/data/repositories/attachment_repository.dart';
import 'package:bean_count/data/repositories/category_repository.dart';
import 'package:bean_count/data/repositories/transaction_repository.dart';
import 'package:bean_count/pages/transactions_page.dart';
import 'package:bean_count/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'dart:io';
import 'dart:typed_data';

void main() {
  late AppDatabase db;
  late TransactionRepository repo;
  late CategoryRepository categories;
  late Directory tmp;
  late AttachmentRepository attachments;

  setUp(() async {
    db = AppDatabase(openInMemoryConnection());
    repo = TransactionRepository(db);
    categories = CategoryRepository(db);
    tmp = await Directory.systemTemp.createTemp('bean_page_attachments');
    attachments = AttachmentRepository(db, directory: tmp);
    await db.select(db.transactions).get(); // 建库 + 种子
  });

  tearDown(() async {
    await db.close();
    if (await tmp.exists()) await tmp.delete(recursive: true);
  });

  Future<void> pumpPage(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: buildBeanTheme(Brightness.light),
        home: Scaffold(
          body: TransactionsPage(
            repository: repo,
            attachments: attachments,
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
  }

  testWidgets('空账本显示「还没有记账」而不是空白或演示数据', (tester) async {
    await pumpPage(tester);
    expect(find.text('还没有记账'), findsOneWidget);
    expect(find.text('点下方的金豆，记下第一笔'), findsOneWidget);
  });

  testWidgets('保存后当天分组里立刻出现这笔', (tester) async {
    final food = await categories.findByName('餐饮', CategoryType.expense);
    await repo.create(
      NewTransaction(
        type: EntryType.expense,
        amountCents: 3850,
        categoryId: food!.id,
        happenedAt: DateTime.now(),
        note: '牛肉面',
      ),
    );

    await pumpPage(tester);

    expect(find.text('还没有记账'), findsNothing);
    expect(find.text('牛肉面'), findsOneWidget);
    // 分类名出现在副标题里；金额为 38.50，支出带负号
    expect(find.textContaining('餐饮'), findsWidgets);
    // 概览里的「支出」合计 + 明细行各一处
    expect(find.text('-38.50'), findsNWidgets(2));
    expect(find.textContaining('1 笔支出'), findsOneWidget);
  });

  testWidgets('多天数据按天分组，最近一天在最上面', (tester) async {
    final food = await categories.findByName('餐饮', CategoryType.expense);
    final now = DateTime.now();
    final yesterday = now.subtract(const Duration(days: 1));

    await repo.create(
      NewTransaction(
        type: EntryType.expense,
        amountCents: 1000,
        categoryId: food!.id,
        happenedAt: yesterday,
        note: '昨天那笔',
      ),
    );
    await repo.create(
      NewTransaction(
        type: EntryType.expense,
        amountCents: 2000,
        categoryId: food.id,
        happenedAt: now,
        note: '今天那笔',
      ),
    );

    await pumpPage(tester);

    expect(find.text('今天那笔'), findsOneWidget);
    expect(find.text('昨天那笔'), findsOneWidget);
    expect(find.textContaining('今天 ·'), findsOneWidget);
    expect(find.textContaining('昨天 ·'), findsOneWidget);

    // 今天排在昨天前面
    final todayY = tester.getTopLeft(find.text('今天那笔')).dy;
    final yesterdayY = tester.getTopLeft(find.text('昨天那笔')).dy;
    expect(todayY, lessThan(yesterdayY));
  });

  testWidgets('有附件显示缩略图，没有附件不占位', (tester) async {
    final food = await categories.findByName('餐饮', CategoryType.expense);
    final withImage = await repo.create(
      NewTransaction(
        type: EntryType.expense,
        amountCents: 1000,
        categoryId: food!.id,
        happenedAt: DateTime.now(),
        note: '带图的一笔',
      ),
    );
    await repo.create(
      NewTransaction(
        type: EntryType.expense,
        amountCents: 2000,
        categoryId: food.id,
        happenedAt: DateTime.now(),
        note: '没图的一笔',
      ),
    );
    // 文件 IO 必须在真实异步里做：widget test 的假时钟不会推进它
    await tester.runAsync(() async {
      await attachments.ensureReady();
      await attachments.add(
        transactionId: withImage.transactionId,
        bytes: Uint8List.fromList(<int>[0x89, 0x50, 0x4E, 0x47]),
        fileName: 'thumb.png',
      );
    });

    await pumpPage(tester);

    // 只有带图的那一行渲染 Image
    expect(find.byType(Image), findsOneWidget);
    expect(find.text('带图的一笔'), findsOneWidget);
    expect(find.text('没图的一笔'), findsOneWidget);
  });
}
