import 'dart:io';

import 'package:bean_count/data/db/app_database.dart';
import 'package:bean_count/data/db/connection.dart';
import 'package:bean_count/data/db/enums.dart';
import 'package:bean_count/data/repositories/attachment_repository.dart';
import 'package:bean_count/data/repositories/category_repository.dart';
import 'package:bean_count/data/repositories/insights_repository.dart';
import 'package:bean_count/data/repositories/transaction_repository.dart';
import 'package:bean_count/pages/category_ledger_page.dart';
import 'package:bean_count/pages/insights_page.dart';
import 'package:bean_count/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late AppDatabase db;
  late TransactionRepository transactions;
  late CategoryRepository categories;
  late InsightsRepository insights;

  setUp(() async {
    db = AppDatabase(openInMemoryConnection());
    transactions = TransactionRepository(db);
    categories = CategoryRepository(db);
    insights = InsightsRepository(db);
    await db.select(db.categories).get();
  });

  tearDown(() async => db.close());

  Future<Category> cat(String name) async =>
      (await categories.findByName(name, CategoryType.expense))!;

  Future<void> pump(WidgetTester tester, Widget child) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.75;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(theme: buildBeanTheme(Brightness.light), home: child),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
  }

  testWidgets('显示合计、笔数、占比与逐笔', (tester) async {
    final eat = await cat('餐饮');
    await transactions.create(
      NewTransaction(
        type: EntryType.expense,
        amountCents: 3850,
        categoryId: eat.id,
        happenedAt: DateTime(2026, 10, 17, 12),
        note: '牛肉面',
      ),
    );
    await transactions.create(
      NewTransaction(
        type: EntryType.expense,
        amountCents: 2500,
        categoryId: eat.id,
        happenedAt: DateTime(2026, 10, 16, 19),
        note: '外卖',
      ),
    );

    await pump(
      tester,
      CategoryLedgerPage(
        category: eat,
        repository: transactions,
        from: DateTime(2026, 10),
        to: DateTime(2026, 11),
        rangeLabel: '2026年10月',
        shareOfPeriod: 0.31,
      ),
    );

    expect(find.text('¥63.50'), findsOneWidget);
    expect(find.textContaining('2 笔'), findsOneWidget);
    expect(find.textContaining('占 31%'), findsOneWidget);
    expect(find.text('牛肉面'), findsOneWidget);
    expect(find.text('外卖'), findsOneWidget);

    // 点一行进详情
    await tester.tap(find.text('牛肉面'));
    await tester.pumpAndSettle();
    // 详情页标题是收支类型，正文里能看到备注与金额
    expect(find.text('支出'), findsWidgets);
    expect(find.text('牛肉面'), findsWidgets);
  });

  testWidgets('空分类显示空状态', (tester) async {
    final eat = await cat('餐饮');
    await pump(
      tester,
      CategoryLedgerPage(
        category: eat,
        repository: transactions,
        rangeLabel: '2026年10月',
      ),
    );

    expect(find.text('这段时间没有这一类支出'), findsOneWidget);
  });

  testWidgets('期间只包含区间内的账目', (tester) async {
    final eat = await cat('餐饮');
    await transactions.create(
      NewTransaction(
        type: EntryType.expense,
        amountCents: 1000,
        categoryId: eat.id,
        happenedAt: DateTime(2026, 9, 30, 20),
        note: '九月末',
      ),
    );
    await transactions.create(
      NewTransaction(
        type: EntryType.expense,
        amountCents: 2000,
        categoryId: eat.id,
        happenedAt: DateTime(2026, 10, 2, 12),
        note: '十月',
      ),
    );

    await pump(
      tester,
      CategoryLedgerPage(
        category: eat,
        repository: transactions,
        from: DateTime(2026, 10),
        to: DateTime(2026, 11),
        rangeLabel: '2026年10月',
      ),
    );

    expect(find.text('十月'), findsOneWidget);
    expect(find.text('九月末'), findsNothing);
    expect(find.text('¥20.00'), findsOneWidget);
  });

  testWidgets('洞察页点分类进入下钻页', (tester) async {
    final eat = await cat('餐饮');
    await transactions.create(
      NewTransaction(
        type: EntryType.expense,
        amountCents: 3850,
        categoryId: eat.id,
        happenedAt: DateTime.now(),
        note: '今天的午饭',
      ),
    );

    await pump(
      tester,
      Scaffold(
        body: InsightsPage(
        repository: insights,
        transactions: transactions,
        attachments: AttachmentRepository(
          db,
          directory: Directory.systemTemp,
        ),
        categories: await categories.allCategories(),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('餐饮'), findsWidgets);
    await tester.tap(find.text('餐饮').last);
    await tester.pumpAndSettle();

    expect(find.text('今天的午饭'), findsOneWidget);
    expect(find.textContaining('1 笔'), findsOneWidget);
  });
}
