import 'package:bean_count/data/db/app_database.dart';
import 'package:bean_count/data/db/connection.dart';
import 'package:bean_count/data/db/enums.dart';
import 'package:bean_count/data/repositories/category_repository.dart';
import 'package:bean_count/data/repositories/recurring_repository.dart';
import 'package:bean_count/data/repositories/transaction_repository.dart';
import 'package:bean_count/pages/shell.dart';
import 'package:bean_count/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

/// 真机/模拟器：真实库已升到 v3，且「打开 App 补记」确实把规则变成交易。
///
/// 运行：flutter test integration_test/recurring_flow_test.dart -d emulator-5554
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  test('真实应用库已迁移到 schemaVersion 3', () async {
    final db = AppDatabase(openDatabaseConnection());
    await db.select(db.accounts).get();
    final version = await db.customSelect('PRAGMA user_version').getSingle();
    expect(version.data.values.first, 3);

    final table = await db.customSelect(
      "SELECT name FROM sqlite_master WHERE type = 'table' "
      "AND name = 'recurring_rules'",
    ).get();
    expect(table, hasLength(1));

    final columns = await db.customSelect(
      "SELECT name FROM pragma_table_info('transactions')",
    ).get();
    final names = columns.map((r) => r.read<String>('name')).toSet();
    expect(names, contains('recurring_rule_id'));
    expect(names, contains('recurring_period'));
    await db.close();
  });

  testWidgets('打开 App 补记到期规则；暂停后不再补', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.75;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final db = AppDatabase(openInMemoryConnection());
    final rules = RecurringRepository(db);
    final categories = CategoryRepository(db);
    final transactions = TransactionRepository(db);
    await db.select(db.categories).get();

    final food = (await categories.findByName('餐饮', CategoryType.expense))!;
    final now = DateTime.now();
    final lastMonth = DateTime(now.year, now.month - 1);

    final rule = await rules.create(
      type: EntryType.expense,
      amountCents: 250000,
      categoryId: food.id,
      note: '房租',
      dayOfMonth: 1,
      startYear: lastMonth.year,
      startMonth: lastMonth.month,
    );

    Future<void> mountShell() async {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpWidget(
        MaterialApp(
          theme: buildBeanTheme(Brightness.light),
          home: ShellPage(database: db),
        ),
      );
      await tester.pumpAndSettle();
      // 补记是异步的，多推几帧等它落库
      for (var i = 0; i < 6; i++) {
        await tester.pump(const Duration(milliseconds: 80));
      }
    }

    await mountShell();

    // 上月 1 日与本月 1 日都在（今天一定 >= 本月 1 日）
    final created = await transactions.count();
    expect(created, greaterThanOrEqualTo(1));
    expect(find.text('房租'), findsWidgets);

    // 暂停后再挂载：不再新增
    await rules.setEnabled(rule.id, false);
    await mountShell();
    expect(await transactions.count(), created, reason: '暂停的规则不补记');

    await db.close();
  });
}
