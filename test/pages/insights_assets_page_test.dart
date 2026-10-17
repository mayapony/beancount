import 'package:bean_count/data/db/app_database.dart';
import 'package:bean_count/data/db/connection.dart';
import 'package:bean_count/data/db/enums.dart';
import 'package:bean_count/data/repositories/account_repository.dart';
import 'package:bean_count/data/repositories/category_repository.dart';
import 'package:bean_count/data/repositories/insights_repository.dart';
import 'package:bean_count/data/repositories/transaction_repository.dart';
import 'package:bean_count/pages/assets_page.dart';
import 'package:bean_count/pages/insights_page.dart';
import 'package:bean_count/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late AppDatabase db;
  late TransactionRepository transactions;
  late CategoryRepository categories;
  late InsightsRepository insights;
  late AccountRepository accounts;

  setUp(() async {
    db = AppDatabase(openInMemoryConnection());
    transactions = TransactionRepository(db);
    categories = CategoryRepository(db);
    insights = InsightsRepository(db);
    accounts = AccountRepository(db);
    await db.select(db.transactions).get();
  });

  tearDown(() async => db.close());

  Future<void> pump(WidgetTester tester, Widget page) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: buildBeanTheme(Brightness.light),
        home: Scaffold(body: page),
      ),
    );
    await tester.pump();
    await tester.pump();
  }

  testWidgets('洞察页总额等于库里支出之和，分类出现在排行里', (tester) async {
    final food = (await categories.findByName('餐饮', CategoryType.expense))!;
    final transport =
        (await categories.findByName('交通', CategoryType.expense))!;

    for (final (cents, category) in [(3850, food), (1200, transport)]) {
      await transactions.create(
        NewTransaction(
          type: EntryType.expense,
          amountCents: cents,
          categoryId: category.id,
          happenedAt: DateTime.now(),
          note: '测试',
        ),
      );
    }

    await pump(tester, InsightsPage(repository: insights));

    // 标题就是本月支出合计 38.50 + 12.00
    expect(find.textContaining('¥50.50'), findsOneWidget);
    expect(find.text('分类占比'), findsOneWidget);
    expect(find.text('餐饮'), findsWidgets);
    expect(find.text('交通'), findsWidgets);
  });

  testWidgets('资产页显示账户与推导出来的余额', (tester) async {
    final account = await accounts.ensure(name: '日常钱包');
    final food = (await categories.findByName('餐饮', CategoryType.expense))!;
    await transactions.create(
      NewTransaction(
        type: EntryType.expense,
        amountCents: 3850,
        categoryId: food.id,
        accountId: account.id,
        happenedAt: DateTime.now(),
        note: '午餐',
      ),
    );

    await pump(tester, AssetsPage(repository: accounts));

    expect(find.text('日常钱包'), findsOneWidget);
    // 大标题（净资产）+ 总负债卡片 + 账户行
    expect(find.text('-¥38.50'), findsNWidgets(3));
    // 总资产 0 + 默认账户 0
    expect(find.text('¥0.00'), findsNWidgets(2));
  });

  testWidgets('资产页空账户列表显示空状态', (tester) async {
    // 把种子账户也删掉，模拟"没有账户"
    await db.delete(db.accounts).go();

    await pump(tester, AssetsPage(repository: accounts));

    expect(find.text('还没有账户'), findsOneWidget);
  });
}
