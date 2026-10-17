import 'package:bean_count/data/db/app_database.dart';
import 'package:bean_count/data/db/connection.dart';
import 'package:bean_count/data/db/enums.dart';
import 'package:bean_count/data/repositories/account_repository.dart';
import 'package:bean_count/data/repositories/attachment_repository.dart';
import 'package:bean_count/data/repositories/category_repository.dart';
import 'package:bean_count/data/repositories/transaction_repository.dart';
import 'package:bean_count/pages/attachment_viewer_page.dart';
import 'package:bean_count/pages/transaction_detail_page.dart';
import 'package:bean_count/pages/transactions_page.dart';
import 'package:bean_count/theme/app_theme.dart';
import 'package:bean_count/utils/month.dart';
import 'package:bean_count/widgets/month_picker_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'dart:io';
import 'dart:typed_data';

void main() {
  late AppDatabase db;
  late TransactionRepository repo;
  late CategoryRepository categories;
  late AccountRepository accounts;
  late Directory tmp;
  late AttachmentRepository attachments;

  setUp(() async {
    db = AppDatabase(openInMemoryConnection());
    repo = TransactionRepository(db);
    categories = CategoryRepository(db);
    accounts = AccountRepository(db);
    tmp = await Directory.systemTemp.createTemp('bean_page_attachments');
    attachments = AttachmentRepository(db, directory: tmp);
    await db.select(db.transactions).get(); // 建库 + 种子
  });

  tearDown(() async {
    await db.close();
    if (await tmp.exists()) await tmp.delete(recursive: true);
  });

  Future<void> pumpPage(WidgetTester tester, {LedgerMonth? month}) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: buildBeanTheme(Brightness.light),
        home: Scaffold(
          body: TransactionsPage(
            repository: repo,
            attachments: attachments,
            categories: categories,
            accounts: accounts,
            initialMonth: month,
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

  testWidgets('指定月份时标题与合计只反映该月', (tester) async {
    final food = await categories.findByName('餐饮', CategoryType.expense);
    await repo.create(
      NewTransaction(
        type: EntryType.expense,
        amountCents: 1000,
        categoryId: food!.id,
        happenedAt: DateTime(2026, 9, 10, 9),
        note: '9月那笔',
      ),
    );
    await repo.create(
      NewTransaction(
        type: EntryType.expense,
        amountCents: 2000,
        categoryId: food.id,
        happenedAt: DateTime(2026, 10, 10, 9),
        note: '10月那笔',
      ),
    );
    await repo.create(
      NewTransaction(
        type: EntryType.expense,
        amountCents: 3000,
        categoryId: food.id,
        happenedAt: DateTime(2026, 10, 11, 9),
        note: '10月第二笔',
      ),
    );

    await pumpPage(tester, month: const LedgerMonth(2026, 10));

    expect(find.text('10月'), findsOneWidget);
    expect(find.text('10月那笔'), findsOneWidget);
    expect(find.text('10月第二笔'), findsOneWidget);
    expect(find.text('9月那笔'), findsNothing);
    expect(find.textContaining('2 笔支出'), findsOneWidget);
  });

  testWidgets('默认落在当月，不把历史月份混进来', (tester) async {
    final food = await categories.findByName('餐饮', CategoryType.expense);
    await repo.create(
      NewTransaction(
        type: EntryType.expense,
        amountCents: 1000,
        categoryId: food!.id,
        happenedAt: DateTime(2020, 1, 5, 9),
        note: '很久以前',
      ),
    );
    await repo.create(
      NewTransaction(
        type: EntryType.expense,
        amountCents: 2000,
        categoryId: food.id,
        happenedAt: DateTime.now(),
        note: '刚刚这笔',
      ),
    );

    await pumpPage(tester);

    expect(find.text('刚刚这笔'), findsOneWidget);
    expect(find.text('很久以前'), findsNothing);
  });

  testWidgets('空状态分两种：整库空 vs 当月空', (tester) async {
    final current = LedgerMonth.current();
    final previous = current.previous;

    // ① 整库没有任何交易：无论浏览哪个月，都说「还没有记账」
    await pumpPage(tester, month: previous);
    expect(find.text('还没有记账'), findsOneWidget);
    expect(find.text('这个月还没有记账'), findsNothing);

    // ② 当月有一笔，但浏览的是上个月：给「回到本月」出口
    final food = await categories.findByName('餐饮', CategoryType.expense);
    await repo.create(
      NewTransaction(
        type: EntryType.expense,
        amountCents: 2000,
        categoryId: food!.id,
        happenedAt: DateTime.now(),
        note: '刚刚这笔',
      ),
    );

    await pumpPage(tester, month: previous);
    expect(find.text('这个月还没有记账'), findsOneWidget);
    expect(find.text('回到本月'), findsOneWidget);
    expect(find.text('刚刚这笔'), findsNothing);

    await tester.tap(find.text('回到本月'));
    await tester.pump();
    await tester.pump();
    expect(find.text('刚刚这笔'), findsOneWidget);
  });

  testWidgets('月份按钮打开选择器，选完切到该月', (tester) async {
    final food = await categories.findByName('餐饮', CategoryType.expense);
    final previous = LedgerMonth.current().previous;
    await repo.create(
      NewTransaction(
        type: EntryType.expense,
        amountCents: 1000,
        categoryId: food!.id,
        happenedAt: DateTime(previous.year, previous.month, 15, 9),
        note: '上个月那笔',
      ),
    );
    await repo.create(
      NewTransaction(
        type: EntryType.expense,
        amountCents: 2000,
        categoryId: food.id,
        happenedAt: DateTime.now(),
        note: '当月那笔',
      ),
    );

    await pumpPage(tester);
    expect(find.text('当月那笔'), findsOneWidget);

    await tester.tap(find.byTooltip('切换月份'));
    await tester.pumpAndSettle();
    expect(find.text('选择月份'), findsOneWidget);

    await tester.tap(
      find.descendant(
        of: find.byType(MonthPickerSheet),
        matching: find.text('${previous.month}月'),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('上个月那笔'), findsOneWidget);
    expect(find.text('当月那笔'), findsNothing);
  });

  testWidgets('左右滑动切换相邻月份', (tester) async {
    final food = await categories.findByName('餐饮', CategoryType.expense);
    final current = LedgerMonth.current();
    final next = current.next;

    await repo.create(
      NewTransaction(
        type: EntryType.expense,
        amountCents: 2000,
        categoryId: food!.id,
        happenedAt: DateTime.now(),
        note: '当月那笔',
      ),
    );
    await repo.create(
      NewTransaction(
        type: EntryType.expense,
        amountCents: 3000,
        categoryId: food.id,
        happenedAt: DateTime(next.year, next.month, 5, 9),
        note: '下月那笔',
      ),
    );

    await pumpPage(tester);
    expect(find.text('当月那笔'), findsOneWidget);

    // 向左甩：切到下个月
    await tester.fling(find.byType(ListView), const Offset(-320, 0), 1200);
    await tester.pumpAndSettle();
    expect(find.text('下月那笔'), findsOneWidget);
    expect(find.text('当月那笔'), findsNothing);

    // 向右甩：回到当月
    await tester.fling(find.byType(ListView), const Offset(320, 0), 1200);
    await tester.pumpAndSettle();
    expect(find.text('当月那笔'), findsOneWidget);
  });

  /// 有多步真实异步（DB / 文件）时 pumpAndSettle 等不到，手动多推几帧。
  Future<void> pumpFrames(WidgetTester tester) async {
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 40));
    }
  }

  testWidgets('点一行进入详情页', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.75;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

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
    await tester.tap(find.text('牛肉面'));
    await pumpFrames(tester);

    expect(find.byType(TransactionDetailPage), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(TransactionDetailPage),
        matching: find.text('-38.50'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('点缩略图走图片查看，不进详情页', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.75;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final food = await categories.findByName('餐饮', CategoryType.expense);
    final withImage = await repo.create(
      NewTransaction(
        type: EntryType.expense,
        amountCents: 3850,
        categoryId: food!.id,
        happenedAt: DateTime.now(),
        note: '牛肉面',
      ),
    );
    await tester.runAsync(() async {
      await attachments.ensureReady();
      await attachments.add(
        transactionId: withImage.transactionId,
        bytes: Uint8List.fromList(<int>[0x89, 0x50, 0x4E, 0x47]),
        fileName: 'thumb.png',
      );
    });

    await pumpPage(tester);
    await tester.tap(find.byType(Image));
    await pumpFrames(tester);

    expect(find.byType(TransactionDetailPage), findsNothing);
    expect(find.byType(AttachmentViewerPage), findsOneWidget);
  });

  testWidgets('删除后该行与缩略图从明细消失', (tester) async {
    final food = await categories.findByName('餐饮', CategoryType.expense);
    final created = await repo.create(
      NewTransaction(
        type: EntryType.expense,
        amountCents: 1200,
        categoryId: food!.id,
        happenedAt: DateTime.now(),
        note: '带图的一笔',
      ),
    );
    await tester.runAsync(() async {
      await attachments.ensureReady();
      await attachments.add(
        transactionId: created.transactionId,
        bytes: Uint8List.fromList(<int>[0x89, 0x50, 0x4E, 0x47]),
        fileName: 'gone.png',
      );
    });

    await pumpPage(tester);
    expect(find.text('带图的一笔'), findsOneWidget);
    expect(find.byType(Image), findsOneWidget);

    // 删除要走真实文件 IO，放在 runAsync 里；明细靠数据流自动重发
    await tester.runAsync(() => repo.delete(created.transactionId));
    await pumpFrames(tester);

    expect(find.text('带图的一笔'), findsNothing);
    expect(find.byType(Image), findsNothing);
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
