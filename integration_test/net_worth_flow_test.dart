import 'package:bean_count/data/db/app_database.dart';
import 'package:bean_count/data/db/connection.dart';
import 'package:bean_count/data/db/enums.dart';
import 'package:bean_count/data/repositories/category_repository.dart';
import 'package:bean_count/data/repositories/transaction_repository.dart';
import 'package:bean_count/pages/shell.dart';
import 'package:bean_count/theme/app_theme.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

/// 真机/模拟器：资产页的净资产走势确实由账目画出来，且改账后跟着变。
///
/// 运行：flutter test integration_test/net_worth_flow_test.dart -d emulator-5554
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('资产页出现净值曲线；改一笔金额后曲线重画', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.75;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final db = AppDatabase(openInMemoryConnection());
    final categories = CategoryRepository(db);
    final transactions = TransactionRepository(db);
    await db.select(db.categories).get();

    final salary = (await categories.findByName('工资', CategoryType.income))!;
    final food = (await categories.findByName('餐饮', CategoryType.expense))!;
    final now = DateTime.now();

    final income = await transactions.create(
      NewTransaction(
        type: EntryType.income,
        amountCents: 500000,
        categoryId: salary.id,
        happenedAt: now,
        note: '工资',
      ),
    );
    await transactions.create(
      NewTransaction(
        type: EntryType.expense,
        amountCents: 120000,
        categoryId: food.id,
        happenedAt: now,
        note: '吃饭',
      ),
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: buildBeanTheme(Brightness.light),
        home: ShellPage(database: db),
      ),
    );
    await tester.pumpAndSettle();

    // 切到资产页
    await tester.tap(find.text('资产').last);
    await tester.pumpAndSettle();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('净资产走势'), findsOneWidget);
    expect(find.byType(LineChart), findsOneWidget);

    // 近 6 个月里，起点月还没有交易，所以变化额 = 当前净值
    expect(find.textContaining('+3,800.00'), findsOneWidget);

    // 切到「全部」仍能画
    await tester.tap(find.text('全部'));
    await tester.pumpAndSettle();
    expect(find.byType(LineChart), findsOneWidget);

    // 切回近 6 月（「全部」从最早一笔所在月开始，变化额恒为 0）
    await tester.tap(find.text('近6月'));
    await tester.pumpAndSettle();

    // 改一笔金额（1200 → 2000 元支出），曲线重画且变化额更新
    final rows = await transactions.exportRows();
    final expense = rows.firstWhere((r) => r.transaction.type == EntryType.expense);
    await transactions.update(
      expense.transaction.id,
      TransactionEdit(
        type: EntryType.expense,
        amountCents: 200000,
        categoryId: expense.transaction.categoryId,
        happenedAt: expense.transaction.happenedAt,
        note: '吃饭（改）',
      ),
    );
    await tester.pumpAndSettle();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.textContaining('+3,000.00'), findsOneWidget);
    expect(income.inserted, isTrue);

    await db.close();
  });
}
