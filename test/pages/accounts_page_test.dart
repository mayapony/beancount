import 'package:bean_count/data/db/app_database.dart';
import 'package:bean_count/data/db/connection.dart';
import 'package:bean_count/data/db/enums.dart';
import 'package:bean_count/data/repositories/account_repository.dart';
import 'package:bean_count/data/repositories/category_repository.dart';
import 'package:bean_count/data/repositories/transaction_repository.dart';
import 'package:bean_count/pages/accounts_page.dart';
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
    await db.select(db.accounts).get();
  });

  tearDown(() async => db.close());

  Future<void> pumpPage(WidgetTester tester) async {
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
    await tester.pump();
  }

  testWidgets('列出账户名称、类型、笔数与余额', (tester) async {
    final wallet = await accounts.create(
      name: '招商银行卡',
      type: AccountType.debit,
      initialBalanceCents: 2856000,
    );
    final food = (await categories.findByName('餐饮', CategoryType.expense))!;
    await transactions.create(
      NewTransaction(
        type: EntryType.expense,
        amountCents: 3850,
        categoryId: food.id,
        accountId: wallet.id,
        happenedAt: DateTime(2026, 10, 17, 12),
        note: '牛肉面',
      ),
    );

    await pumpPage(tester);

    expect(find.text('招商银行卡'), findsOneWidget);
    expect(find.text('储蓄卡 · 1 笔'), findsOneWidget);
    expect(find.text('28,521.50'), findsOneWidget);
  });

  testWidgets('新建账户后出现在列表', (tester) async {
    await pumpPage(tester);

    await tester.tap(find.byTooltip('新建账户'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, '支付宝');
    await tester.tap(find.text('信用卡'));
    await tester.enterText(find.byType(TextField).last, '1000');
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();

    expect(find.text('支付宝'), findsOneWidget);
    final created = (await accounts.all()).firstWhere((a) => a.name == '支付宝');
    expect(created.type, AccountType.credit);
    expect(created.initialBalanceCents, 100000);
  });

  testWidgets('改期初余额后当前余额随之变化', (tester) async {
    final wallet = await accounts.create(
      name: '钱包',
      initialBalanceCents: 100000,
    );
    final food = (await categories.findByName('餐饮', CategoryType.expense))!;
    await transactions.create(
      NewTransaction(
        type: EntryType.expense,
        amountCents: 3850,
        categoryId: food.id,
        accountId: wallet.id,
        happenedAt: DateTime(2026, 10, 17, 12),
        note: '牛肉面',
      ),
    );

    await pumpPage(tester);
    expect(find.text('961.50'), findsOneWidget);

    await tester.tap(find.text('钱包'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, '2000');
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();

    expect(find.text('1,961.50'), findsOneWidget);
    expect(await transactions.count(), 1, reason: '改期初不动交易');
  });

  testWidgets('删除有交易的账户：提示笔数且不删除', (tester) async {
    final wallet = await accounts.create(name: '钱包');
    final food = (await categories.findByName('餐饮', CategoryType.expense))!;
    await transactions.create(
      NewTransaction(
        type: EntryType.expense,
        amountCents: 1000,
        categoryId: food.id,
        accountId: wallet.id,
        happenedAt: DateTime(2026, 10, 17, 9),
        note: '一笔',
      ),
    );

    await pumpPage(tester);
    await tester.tap(find.text('钱包'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('删除账户'));
    await tester.pumpAndSettle();

    expect(find.textContaining('有 1 笔交易在使用该账户'), findsOneWidget);
    expect(await accounts.byId(wallet.id), isNotNull);
  });

  testWidgets('删除没有交易的账户直接生效', (tester) async {
    final empty = await accounts.create(name: '空账户');
    await pumpPage(tester);

    await tester.tap(find.text('空账户'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('删除账户'));
    await tester.pumpAndSettle();

    expect(find.text('空账户'), findsNothing);
    expect(await accounts.byId(empty.id), isNull);
  });
}
