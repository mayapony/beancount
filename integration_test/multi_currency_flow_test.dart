import 'package:bean_count/data/db/app_database.dart';
import 'package:bean_count/data/db/connection.dart';
import 'package:bean_count/data/db/enums.dart';
import 'package:bean_count/data/repositories/account_repository.dart';
import 'package:bean_count/data/repositories/category_repository.dart';
import 'package:bean_count/data/repositories/insights_repository.dart';
import 'package:bean_count/data/repositories/transaction_repository.dart';
import 'package:bean_count/pages/shell.dart';
import 'package:bean_count/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

/// 真机/模拟器：USD 账户 + 外币交易 → 明细显示原币，洞察按本位币合计。
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('外币交易：明细显示原币，统计按本位币', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.75;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final db = AppDatabase(openInMemoryConnection());
    final accounts = AccountRepository(db);
    final categories = CategoryRepository(db);
    final transactions = TransactionRepository(db);
    final insights = InsightsRepository(db);
    await db.select(db.categories).get();

    final card = await accounts.create(name: 'USD 卡', currency: 'USD');
    final food = (await categories.findByName('餐饮', CategoryType.expense))!;
    await transactions.create(
      NewTransaction(
        type: EntryType.expense,
        amountCents: 10000,
        currency: 'USD',
        originalAmountCents: 10000,
        ratePpm: 7250000,
        categoryId: food.id,
        accountId: card.id,
        happenedAt: DateTime.now(),
        note: '纽约晚饭',
      ),
    );

    // 统计按本位币 725 元
    final stats = await insights.load(period: InsightsPeriod.month);
    expect(stats.expenseCents, 72500);

    await tester.pumpWidget(
      MaterialApp(
        theme: buildBeanTheme(Brightness.light),
        home: ShellPage(database: db),
      ),
    );
    await tester.pumpAndSettle();
    await tester.pump(const Duration(milliseconds: 300));

    // 明细：原币 + 折合
    expect(find.text(r'US$100.00'), findsOneWidget);
    expect(find.text('≈ ¥725.00'), findsOneWidget);

    await db.close();
  });
}
