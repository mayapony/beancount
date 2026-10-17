import 'package:bean_count/data/db/app_database.dart';
import 'package:bean_count/data/db/connection.dart';
import 'package:bean_count/data/db/enums.dart';
import 'package:bean_count/data/repositories/account_repository.dart';
import 'package:bean_count/data/repositories/category_repository.dart';
import 'package:bean_count/data/repositories/transaction_repository.dart';
import 'package:bean_count/pages/shell.dart';
import 'package:bean_count/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

/// 真机/模拟器：信用卡设还款日 + 刷一笔 → 资产页出现「待还」与天数。
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('信用卡账单提醒出现在资产页', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.75;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final db = AppDatabase(openInMemoryConnection());
    final accounts = AccountRepository(db);
    final categories = CategoryRepository(db);
    final transactions = TransactionRepository(db);
    await db.select(db.categories).get();

    final card = await accounts.create(
      name: '招商信用卡',
      type: AccountType.credit,
      billingDay: 5,
      dueDay: 20,
    );
    final food = (await categories.findByName('餐饮', CategoryType.expense))!;
    await transactions.create(
      NewTransaction(
        type: EntryType.expense,
        amountCents: 320000,
        categoryId: food.id,
        accountId: card.id,
        happenedAt: DateTime.now(),
        note: '刷卡消费',
      ),
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: buildBeanTheme(Brightness.light),
        home: ShellPage(database: db),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('资产').last);
    await tester.pumpAndSettle();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('待还'), findsOneWidget);
    expect(find.text('招商信用卡'), findsWidgets);
    expect(find.text('¥3,200.00'), findsOneWidget);
    // 20 号到期：今天之前是「还有 N 天」，今天正好 20 号则是「今天到期」
    expect(
      find.textContaining('天').evaluate().isNotEmpty ||
          find.text('今天到期').evaluate().isNotEmpty,
      isTrue,
    );

    await db.close();
  });
}
