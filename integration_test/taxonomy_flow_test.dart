import 'dart:io';

import 'package:bean_count/data/db/app_database.dart';
import 'package:bean_count/data/db/enums.dart';
import 'package:bean_count/data/repositories/account_repository.dart';
import 'package:bean_count/data/repositories/category_repository.dart';
import 'package:bean_count/data/repositories/transaction_repository.dart';
import 'package:bean_count/pages/accounts_page.dart';
import 'package:bean_count/pages/categories_page.dart';
import 'package:bean_count/theme/app_theme.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// 真机/模拟器：分类与账户管理在真实文件库上走一遍，并验证重启后仍在。
///
/// 运行：flutter test integration_test/taxonomy_flow_test.dart -d emulator-5554
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  late File dbFile;
  late AppDatabase db;
  late CategoryRepository categories;
  late AccountRepository accounts;
  late TransactionRepository transactions;

  AppDatabase open() => AppDatabase(NativeDatabase(dbFile));

  setUp(() async {
    final dir = await getApplicationDocumentsDirectory();
    dbFile = File(p.join(dir.path, 'it_taxonomy.sqlite'));
    if (await dbFile.exists()) await dbFile.delete();

    db = open();
    categories = CategoryRepository(db);
    accounts = AccountRepository(db);
    transactions = TransactionRepository(db);
    await db.select(db.categories).get();
  });

  tearDown(() async {
    await db.close();
    if (await dbFile.exists()) await dbFile.delete();
  });

  Future<void> pump(WidgetTester tester, Widget page) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.75;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    // 先清空再挂载：同类型页面在同一位置会复用 State，不会重新 initState
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpWidget(
      MaterialApp(theme: buildBeanTheme(Brightness.light), home: page),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('分类：新建二级 → 记账 → 改名 → 迁移删除', (tester) async {
    await pump(tester, CategoriesPage(repository: categories));

    // 新建「外卖」，挂到「餐饮」下
    await tester.tap(find.byTooltip('新建分类'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '外卖');
    await tester.tap(find.text('餐饮').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();
    expect(find.text('外卖'), findsOneWidget);

    final food = (await categories.findByName('餐饮', CategoryType.expense))!;
    final takeout = (await categories.findByName(
      '外卖',
      CategoryType.expense,
      parentId: food.id,
    ))!;

    // 用它记一笔（模拟记账流程写入）
    await transactions.create(
      NewTransaction(
        type: EntryType.expense,
        amountCents: 3850,
        categoryId: takeout.id,
        happenedAt: DateTime(2026, 10, 17, 12, 30),
        note: '麻辣烫',
      ),
    );

    // 改名「餐饮」→「吃饭」
    await tester.tap(find.text('餐饮'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '吃饭');
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();
    expect(find.text('吃饭'), findsOneWidget);

    // 删除「吃饭」：有交易 → 迁移到「交通」
    await tester.tap(find.byTooltip('删除').first);
    await tester.pumpAndSettle();
    expect(find.text('迁移到'), findsOneWidget);
    await tester.tap(find.text('交通').last);
    await tester.pumpAndSettle();

    final target = (await categories.findByName('交通', CategoryType.expense))!;
    expect(await categories.byId(food.id), isNull);
    expect(await transactions.count(), 1);
    expect(await categories.transactionCount(target.id), 1);

    // 重开库：改名与迁移都在
    await db.close();
    db = open();
    categories = CategoryRepository(db);
    transactions = TransactionRepository(db);
    await db.select(db.categories).get();
    expect(await categories.findByName('吃饭', CategoryType.expense), isNull);
    expect(await categories.findByName('交通', CategoryType.expense), isNotNull);
    expect(await transactions.count(), 1);
  });

  testWidgets('账户：新建 → 改期初 → 删除；有交易时拒删', (tester) async {
    await pump(tester, AccountsPage(repository: accounts));

    // 新建账户
    await tester.tap(find.byTooltip('新建账户'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, '支付宝');
    await tester.enterText(find.byType(TextField).last, '1000');
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();
    expect(find.text('支付宝'), findsOneWidget);

    final created = (await accounts.all()).firstWhere((a) => a.name == '支付宝');

    // 记一笔后余额 = 1000 - 38.50（换一棵新树刷新页面）
    final food = (await categories.findByName('餐饮', CategoryType.expense))!;
    await transactions.create(
      NewTransaction(
        type: EntryType.expense,
        amountCents: 3850,
        categoryId: food.id,
        accountId: created.id,
        happenedAt: DateTime(2026, 10, 17, 12),
        note: '牛肉面',
      ),
    );
    await pump(tester, AccountsPage(repository: accounts));
    expect(find.text('961.50'), findsOneWidget);

    // 有交易：删除被拒
    await tester.tap(find.text('支付宝'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('删除账户'));
    await tester.pumpAndSettle();
    expect(find.textContaining('有 1 笔交易在使用该账户'), findsOneWidget);
    expect(await accounts.byId(created.id), isNotNull);

    // 改期初余额 → 余额变化
    await tester.enterText(find.byType(TextField).last, '2000');
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();
    expect(find.text('1,961.50'), findsOneWidget);

    // 重开库仍在
    await db.close();
    db = open();
    accounts = AccountRepository(db);
    await db.select(db.accounts).get();
    final reopened = (await accounts.all()).firstWhere((a) => a.name == '支付宝');
    expect(reopened.initialBalanceCents, 200000);
  });
}
