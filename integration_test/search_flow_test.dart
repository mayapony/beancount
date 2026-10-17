import 'dart:io';

import 'package:bean_count/data/db/app_database.dart';
import 'package:bean_count/data/db/enums.dart';
import 'package:bean_count/data/repositories/account_repository.dart';
import 'package:bean_count/data/repositories/category_repository.dart';
import 'package:bean_count/data/repositories/transaction_repository.dart';
import 'package:bean_count/pages/search_page.dart';
import 'package:bean_count/pages/transaction_detail_page.dart';
import 'package:bean_count/theme/app_theme.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// 真机/模拟器：搜索在真实文件库上的关键词、筛选与「改完再回来」。
///
/// 运行：flutter test integration_test/search_flow_test.dart -d emulator-5554
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  late File dbFile;
  late AppDatabase db;
  late TransactionRepository transactions;
  late CategoryRepository categories;
  late AccountRepository accounts;

  setUp(() async {
    final dir = await getApplicationDocumentsDirectory();
    dbFile = File(p.join(dir.path, 'it_search.sqlite'));
    if (await dbFile.exists()) await dbFile.delete();

    db = AppDatabase(NativeDatabase(dbFile));
    transactions = TransactionRepository(db);
    categories = CategoryRepository(db);
    accounts = AccountRepository(db);
    await db.select(db.transactions).get();

    final food = (await categories.findByName('餐饮', CategoryType.expense))!;
    final shopping =
        (await categories.findByName('购物', CategoryType.expense))!;
    final salary =
        (await categories.findByName('工资', CategoryType.income))!;
    final wallet = (await accounts.all()).first;

    await transactions.create(NewTransaction(
      type: EntryType.expense,
      amountCents: 3850,
      categoryId: food.id,
      happenedAt: DateTime.now(),
      note: '牛肉面',
      accountId: wallet.id,
      tags: ['出差'],
    ));
    await transactions.create(NewTransaction(
      type: EntryType.expense,
      amountCents: 23600,
      categoryId: shopping.id,
      happenedAt: DateTime.now(),
      note: '超市采购',
    ));
    await transactions.create(NewTransaction(
      type: EntryType.income,
      amountCents: 1451900,
      categoryId: salary.id,
      happenedAt: DateTime.now(),
      note: '工资',
    ));
  });

  tearDown(() async {
    await db.close();
    if (await dbFile.exists()) await dbFile.delete();
  });

  testWidgets('关键词 → 类型筛选 → 分类+金额 → 进详情改金额再返回', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.75;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        theme: buildBeanTheme(Brightness.light),
        home: SearchPage(
          repository: transactions,
          categories: categories,
          accounts: accounts,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('命中 3 笔'), findsOneWidget);

    // 关键词
    await tester.enterText(find.byType(TextField).first, '超市');
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();
    expect(find.text('命中 1 笔'), findsOneWidget);

    // 清空关键词，改用类型筛选
    await tester.enterText(find.byType(TextField).first, '');
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();
    await tester.tap(find.text('收入'));
    await tester.pumpAndSettle();
    expect(find.text('命中 1 笔'), findsOneWidget);
    expect(find.text('工资'), findsWidgets);

    // 回到全部，用「分类 + 金额区间」
    await tester.tap(find.text('全部收支'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('筛选'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('购物'));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextField, '最小'), '100');
    await tester.enterText(find.widgetWithText(TextField, '最大'), '300');
    await tester.tap(find.text('应用'));
    await tester.pumpAndSettle();
    expect(find.text('命中 1 笔'), findsOneWidget);
    expect(find.text('超市采购'), findsOneWidget);

    // 进详情改分类，返回后结果按新值刷新
    await tester.tap(find.text('超市采购'));
    await tester.pumpAndSettle();
    expect(find.byType(TransactionDetailPage), findsOneWidget);

    await tester.tap(find.text('编辑'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('餐饮'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('完成').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('返回'));
    await tester.pumpAndSettle();

    // 分类已改成餐饮，原来的「购物」筛选不再命中
    expect(find.text('命中 0 笔'), findsOneWidget);
    expect(find.text('没有匹配的账目'), findsOneWidget);
  });
}
