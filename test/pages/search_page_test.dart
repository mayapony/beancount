import 'package:bean_count/data/db/app_database.dart';
import 'package:bean_count/data/db/connection.dart';
import 'package:bean_count/data/db/enums.dart';
import 'package:bean_count/data/repositories/account_repository.dart';
import 'package:bean_count/data/repositories/category_repository.dart';
import 'package:bean_count/data/repositories/transaction_repository.dart';
import 'package:bean_count/pages/search_page.dart';
import 'package:bean_count/pages/transaction_detail_page.dart';
import 'package:bean_count/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late AppDatabase db;
  late TransactionRepository repo;
  late CategoryRepository categories;
  late AccountRepository accounts;

  setUp(() async {
    db = AppDatabase(openInMemoryConnection());
    categories = CategoryRepository(db);
    accounts = AccountRepository(db);
    repo = TransactionRepository(db);
    await db.select(db.transactions).get();

    final food = (await categories.findByName('餐饮', CategoryType.expense))!;
    final shopping = (await categories.findByName('购物', CategoryType.expense))!;
    final salary = (await categories.findByName('工资', CategoryType.income))!;
    final wallet = (await accounts.all()).first;

    await repo.create(NewTransaction(
      type: EntryType.expense,
      amountCents: 3850,
      categoryId: food.id,
      happenedAt: DateTime.now(),
      note: '牛肉面',
      accountId: wallet.id,
      tags: ['出差'],
    ));
    await repo.create(NewTransaction(
      type: EntryType.expense,
      amountCents: 23600,
      categoryId: shopping.id,
      happenedAt: DateTime.now(),
      note: '超市采购',
    ));
    await repo.create(NewTransaction(
      type: EntryType.income,
      amountCents: 1451900,
      categoryId: salary.id,
      happenedAt: DateTime(2020, 3, 5, 10),
      note: 'Starbucks 兼职',
    ));
  });

  tearDown(() async => db.close());

  Future<void> pumpSearch(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.75;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        theme: buildBeanTheme(Brightness.light),
        home: SearchPage(
          repository: repo,
          categories: categories,
          accounts: accounts,
        ),
      ),
    );
    for (var i = 0; i < 4; i++) {
      await tester.pump(const Duration(milliseconds: 120));
    }
  }

  testWidgets('输入关键词后结果收敛，命中数可见', (tester) async {
    await pumpSearch(tester);
    expect(find.text('命中 3 笔'), findsOneWidget);

    await tester.enterText(find.byType(TextField).first, '超市');
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();

    expect(find.text('命中 1 笔'), findsOneWidget);
    expect(find.text('超市采购'), findsOneWidget);
    expect(find.text('牛肉面'), findsNothing);
  });

  testWidgets('类型与时间快捷筛选改变结果', (tester) async {
    await pumpSearch(tester);

    await tester.tap(find.text('收入'));
    await tester.pumpAndSettle();
    expect(find.text('命中 1 笔'), findsOneWidget);
    expect(find.text('Starbucks 兼职'), findsOneWidget);

    await tester.tap(find.text('全部收支'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('本月'));
    await tester.pumpAndSettle();
    expect(find.text('命中 2 笔'), findsOneWidget, reason: '2020 年那笔被排除');
  });

  testWidgets('无匹配时显示「没有匹配的账目」', (tester) async {
    await pumpSearch(tester);

    await tester.enterText(find.byType(TextField).first, '不存在的词');
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();

    expect(find.text('没有匹配的账目'), findsOneWidget);
    expect(find.text('命中 0 笔'), findsOneWidget);
  });

  testWidgets('筛选面板：分类 + 金额区间', (tester) async {
    await pumpSearch(tester);

    await tester.tap(find.byTooltip('筛选'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('购物'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, '100');
    await tester.enterText(find.byType(TextField).last, '300');
    await tester.tap(find.text('应用'));
    await tester.pumpAndSettle();

    expect(find.text('命中 1 笔'), findsOneWidget);
    expect(find.text('超市采购'), findsOneWidget);
    expect(find.text('牛肉面'), findsNothing);
  });

  testWidgets('摘要可单条移除、可一键清空（关键词保留）', (tester) async {
    await pumpSearch(tester);

    await tester.enterText(find.byType(TextField).first, '面');
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('筛选'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('餐饮'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('应用'));
    await tester.pumpAndSettle();

    // 关键词「面」+ 分类「餐饮」→ 只有牛肉面
    expect(find.text('命中 1 笔'), findsOneWidget);
    expect(find.text('清空筛选'), findsOneWidget);

    await tester.tap(find.text('清空筛选'));
    await tester.pumpAndSettle();
    expect(find.text('命中 1 笔'), findsOneWidget, reason: '关键词仍在');
    expect(find.text('清空筛选'), findsNothing);
  });

  testWidgets('点结果行进入交易详情', (tester) async {
    await pumpSearch(tester);

    await tester.tap(find.text('牛肉面'));
    await tester.pumpAndSettle();

    expect(find.byType(TransactionDetailPage), findsOneWidget);
  });

  testWidgets('类型筛选「转账」只列出转账', (tester) async {
    final from = (await accounts.all()).first;
    final to = await accounts.ensure(name: '支付宝');
    final food = (await categories.findByName('餐饮', CategoryType.expense))!;
    await repo.create(
      NewTransaction(
        type: EntryType.expense,
        amountCents: 3850,
        categoryId: food.id,
        happenedAt: DateTime.now(),
        note: '牛肉面',
      ),
    );
    await repo.create(
      NewTransaction(
        type: EntryType.transfer,
        amountCents: 50000,
        accountId: from.id,
        toAccountId: to.id,
        happenedAt: DateTime.now(),
        note: '还信用卡',
      ),
    );

    await pumpSearch(tester);
    await tester.tap(find.text('转账'));
    await tester.pumpAndSettle();

    expect(find.text('命中 1 笔'), findsOneWidget);
    expect(find.text('还信用卡'), findsOneWidget);
    expect(find.text('牛肉面'), findsNothing);
  });
}