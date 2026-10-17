import 'package:bean_count/data/db/app_database.dart';
import 'package:bean_count/data/db/connection.dart';
import 'package:bean_count/data/db/enums.dart';
import 'package:bean_count/data/repositories/category_repository.dart';
import 'package:bean_count/data/repositories/transaction_repository.dart';
import 'package:bean_count/pages/shell.dart';
import 'package:bean_count/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

/// 真机/模拟器：洞察页点分类 → 下钻页 → 点一笔进详情 → 返回。
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('分类下钻：洞察 → 分类账目 → 详情', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.75;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final db = AppDatabase(openInMemoryConnection());
    final categories = CategoryRepository(db);
    final transactions = TransactionRepository(db);
    await db.select(db.categories).get();

    final eat = (await categories.findByName('餐饮', CategoryType.expense))!;
    final takeaway =
        await categories.ensure(name: '外卖', type: CategoryType.expense, parentId: eat.id);
    final now = DateTime.now();

    await transactions.create(
      NewTransaction(
        type: EntryType.expense,
        amountCents: 3850,
        categoryId: eat.id,
        happenedAt: DateTime(now.year, now.month, 2, 12),
        note: '堂食午饭',
      ),
    );
    await transactions.create(
      NewTransaction(
        type: EntryType.expense,
        amountCents: 2500,
        categoryId: takeaway.id,
        happenedAt: DateTime(now.year, now.month, 3, 19),
        note: '外卖晚饭',
      ),
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: buildBeanTheme(Brightness.light),
        home: ShellPage(database: db),
      ),
    );
    await tester.pumpAndSettle();

    // 切到洞察
    await tester.tap(find.text('洞察').last);
    await tester.pumpAndSettle();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('分类排行'), findsOneWidget);
    // 图例胶囊在页面上部，先滚到可见再点（排行可能还在屏幕外）
    final chip = find.text('餐饮').first;
    await tester.ensureVisible(chip);
    await tester.pumpAndSettle();
    await tester.tap(chip);
    await tester.pumpAndSettle();
    await tester.pump(const Duration(milliseconds: 300));

    // 下钻页：合计 63.50（含子分类「外卖」）
    expect(find.text('¥63.50'), findsOneWidget);
    expect(find.textContaining('2 笔'), findsOneWidget);
    expect(find.text('外卖晚饭'), findsOneWidget);

    // 点一笔进详情
    await tester.tap(find.text('堂食午饭'));
    await tester.pumpAndSettle();
    expect(find.textContaining('38.50'), findsWidgets);

    // 返回下钻页
    await tester.tap(find.byTooltip('返回'));
    await tester.pumpAndSettle();
    expect(find.text('外卖晚饭'), findsOneWidget);

    await db.close();
  });
}
