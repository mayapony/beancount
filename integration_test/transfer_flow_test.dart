import 'package:bean_count/data/db/app_database.dart';
import 'package:bean_count/data/db/connection.dart';
import 'package:bean_count/data/db/enums.dart';
import 'package:bean_count/data/repositories/account_repository.dart';
import 'package:bean_count/data/repositories/transaction_repository.dart';
import 'package:bean_count/pages/shell.dart';
import 'package:bean_count/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

/// 真机/模拟器：真实应用库已升到 v2，并且转账在 UI 上真的能记、能删。
///
/// 运行：flutter test integration_test/transfer_flow_test.dart -d emulator-5554
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  test('真实应用库已迁移到 schemaVersion 2', () async {
    final db = AppDatabase(openDatabaseConnection());
    // 首次读取会触发迁移（安装新版本后第一次启动）
    await db.select(db.accounts).get();
    final version = await db.customSelect('PRAGMA user_version').getSingle();
    expect(version.data.values.first, 2);

    final columns = await db.customSelect(
      "SELECT name FROM pragma_table_info('transactions')",
    ).get();
    final names = columns.map((r) => r.read<String>('name')).toSet();
    expect(names, contains('to_account_id'));

    // 历史分类与账户仍在
    final categories = await db.select(db.categories).get();
    final accounts = await db.select(db.accounts).get();
    expect(categories, isNotEmpty);
    expect(accounts, isNotEmpty);
    await db.close();
  });

  testWidgets('UI 记一笔转账 → 明细显示 → 删除后消失', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.75;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final db = AppDatabase(openInMemoryConnection());
    final accounts = AccountRepository(db);
    final transactions = TransactionRepository(db);
    await db.select(db.accounts).get();

    final from = (await accounts.all()).first;
    final to = await accounts.create(name: '支付宝');

    await tester.pumpWidget(
      MaterialApp(
        theme: buildBeanTheme(Brightness.light),
        home: ShellPage(database: db),
      ),
    );
    await tester.pumpAndSettle();

    // 金豆 → 转账 → 300 → 完成
    await tester.tap(find.byIcon(Icons.add_rounded));
    await tester.pumpAndSettle();
    await tester.tap(find.text('转账'));
    await tester.pumpAndSettle();
    expect(find.text('从'), findsOneWidget);
    expect(find.text('到'), findsOneWidget);

    for (final key in ['3', '0', '0']) {
      await tester.tap(find.text(key).last);
      await tester.pump();
    }
    await tester.tap(find.text('完成').last);
    await tester.pumpAndSettle();

    // 明细：出现转账行，且不带收入/支出符号
    expect(find.text('300.00'), findsOneWidget);
    expect(find.textContaining('→'), findsWidgets);

    // 账户：两端各 300、各记一笔，净资产不变
    final balances = await accounts.withBalances();
    final fromBalance = balances.firstWhere((b) => b.account.id == from.id);
    final toBalance = balances.firstWhere((b) => b.account.id == to.id);
    expect(fromBalance.balanceCents, -30000);
    expect(toBalance.balanceCents, 30000);
    expect(fromBalance.count, 1);
    expect(toBalance.count, 1);

    // 点进详情删除
    await tester.tap(find.text('300.00').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('删除这笔'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('删除'));
    await tester.pumpAndSettle();

    expect(await transactions.count(), 0);
    final after = await accounts.withBalances();
    expect(
      after.firstWhere((b) => b.account.id == from.id).balanceCents,
      0,
      reason: '删除后余额还原',
    );

    await db.close();
  });
}
