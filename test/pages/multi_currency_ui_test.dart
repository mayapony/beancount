import 'package:bean_count/data/db/app_database.dart';
import 'package:bean_count/data/db/connection.dart';
import 'package:bean_count/data/db/enums.dart';
import 'package:bean_count/data/repositories/account_repository.dart';
import 'package:bean_count/data/repositories/category_repository.dart';
import 'package:bean_count/data/repositories/transaction_repository.dart';
import 'package:bean_count/pages/transaction_detail_page.dart';
import 'package:bean_count/theme/app_theme.dart';
import 'package:bean_count/widgets/quick_entry_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late AppDatabase db;
  late AccountRepository accounts;
  late CategoryRepository categories;
  late TransactionRepository transactions;

  setUp(() async {
    db = AppDatabase(openInMemoryConnection());
    accounts = AccountRepository(db);
    categories = CategoryRepository(db);
    transactions = TransactionRepository(db);
    await db.select(db.categories).get();
  });

  tearDown(() async => db.close());

  testWidgets('外币账户出现汇率行，草稿带原币与汇率', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.75;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final usd = await accounts.create(name: 'USD 卡', currency: 'USD');
    final balances = await accounts.withBalances();
    final allCategories = await categories.allCategories();
    QuickEntryDraft? submitted;

    await tester.pumpWidget(
      MaterialApp(
        theme: buildBeanTheme(Brightness.light),
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () => showModalBottomSheet<void>(
                  context: context,
                  isScrollControlled: true,
                  builder: (_) => QuickEntrySheet(
                    categories: allCategories,
                    accounts: balances,
                    initialAccountId: usd.id,
                    fxRates: const {'USD': 7250000},
                    onSubmit: (draft) async {
                      submitted = draft;
                      return null;
                    },
                  ),
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.text('汇率'), findsOneWidget);
    expect(find.text('1 USD = ¥7.25'), findsOneWidget);

    for (final key in ['1', '0', '0']) {
      await tester.tap(find.text(key).last);
      await tester.pump();
    }
    // 换算预览：100 USD ≈ 725
    expect(find.text('≈ ¥725.00'), findsOneWidget);

    await tester.tap(find.text('完成'));
    await tester.pumpAndSettle();

    expect(submitted?.currency, 'USD');
    expect(submitted?.ratePpm, 7250000);
    expect(submitted?.amount, 100);
  });

  testWidgets('详情页显示原币与汇率', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.75;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final card = await accounts.create(name: 'USD 卡', currency: 'USD');
    final food = (await categories.findByName('餐饮', CategoryType.expense))!;
    final result = await transactions.create(
      NewTransaction(
        type: EntryType.expense,
        amountCents: 10000,
        currency: 'USD',
        originalAmountCents: 10000,
        ratePpm: 7250000,
        categoryId: food.id,
        accountId: card.id,
        happenedAt: DateTime(2026, 10, 8, 12),
        note: '晚饭',
      ),
    );

    final row = (await transactions.byId(result.transactionId))!;
    final allCategories = await categories.allCategories();
    await tester.pumpWidget(
      MaterialApp(
        theme: buildBeanTheme(Brightness.light),
        home: TransactionDetailPage(
          row: row,
          repository: transactions,
          categories: allCategories,
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('原币'), findsOneWidget);
    expect(find.text(r'US$100.00'), findsOneWidget);
    expect(find.text('汇率'), findsOneWidget);
    expect(find.text('1 USD = ¥7.25'), findsOneWidget);
    // 金额头显示折合后的本位币
    expect(find.textContaining('725.00'), findsWidgets);
  });
}
