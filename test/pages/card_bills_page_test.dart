import 'package:bean_count/data/db/app_database.dart';
import 'package:bean_count/data/db/connection.dart';
import 'package:bean_count/data/db/enums.dart';
import 'package:bean_count/data/repositories/account_repository.dart';
import 'package:bean_count/data/repositories/category_repository.dart';
import 'package:bean_count/data/repositories/transaction_repository.dart';
import 'package:bean_count/pages/accounts_page.dart';
import 'package:bean_count/pages/assets_page.dart';
import 'package:bean_count/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late AppDatabase db;
  late AccountRepository accounts;
  late TransactionRepository transactions;
  late CategoryRepository categories;

  setUp(() async {
    db = AppDatabase(openInMemoryConnection());
    accounts = AccountRepository(db);
    transactions = TransactionRepository(db);
    categories = CategoryRepository(db);
    await db.select(db.categories).get();
  });

  tearDown(() async => db.close());

  Future<void> pumpAssets(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.75;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        theme: buildBeanTheme(Brightness.light),
        home: Scaffold(body: AssetsPage(repository: accounts)),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
  }

  testWidgets('信用卡欠款时出现待还提醒', (tester) async {
    final card = await accounts.create(
      name: '招商信用卡',
      type: AccountType.credit,
      dueDay: (DateTime.now().day + 2).clamp(1, 28),
    );
    final food = (await categories.findByName('餐饮', CategoryType.expense))!;
    await transactions.create(
      NewTransaction(
        type: EntryType.expense,
        amountCents: 320000,
        categoryId: food.id,
        accountId: card.id,
        happenedAt: DateTime.now(),
        note: '刷了卡',
      ),
    );

    await pumpAssets(tester);

    expect(find.text('待还'), findsOneWidget);
    expect(find.text('招商信用卡'), findsWidgets);
    expect(find.text('¥3,200.00'), findsOneWidget);
    expect(find.textContaining('还有'), findsOneWidget);
  });

  testWidgets('没有信用卡日期时不显示提醒', (tester) async {
    await accounts.create(name: '储蓄卡', type: AccountType.debit);
    await pumpAssets(tester);

    expect(find.text('待还'), findsNothing);
  });

  testWidgets('已还清的信用卡不提醒', (tester) async {
    await accounts.create(
      name: '已还清卡',
      type: AccountType.credit,
      dueDay: 15,
    );
    await pumpAssets(tester);

    expect(find.text('待还'), findsNothing);
  });

  testWidgets('信用卡编辑页出现账单日/还款日，储蓄卡不出现', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.75;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        theme: buildBeanTheme(Brightness.light),
        home: AccountsPage(repository: accounts),
      ),
    );
    await tester.pump();
    await tester.tap(find.byTooltip('新建账户'));
    await tester.pumpAndSettle();

    // 默认钱包：没有日期输入
    expect(find.text('还款日（1–28）'), findsNothing);

    // 切到信用卡：出现两个日期
    await tester.tap(find.text('信用卡'));
    await tester.pumpAndSettle();
    expect(find.text('账单日（1–28）'), findsOneWidget);
    expect(find.text('还款日（1–28）'), findsOneWidget);

    // 填 31 保存：被拒并提示
    await tester.enterText(find.byType(TextField).at(0), '测试卡');
    await tester.enterText(find.widgetWithText(TextField, '还款日（1–28）'), '31');
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();
    expect(find.textContaining('1–28'), findsWidgets);

    // 改成 20 再保存：成功
    await tester.enterText(find.widgetWithText(TextField, '还款日（1–28）'), '20');
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();

    final created = (await accounts.all()).firstWhere((a) => a.name == '测试卡');
    expect(created.dueDay, 20);
    expect(created.type, AccountType.credit);
  });
}