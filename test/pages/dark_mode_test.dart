import 'package:bean_count/data/db/app_database.dart';
import 'package:bean_count/data/db/connection.dart';
import 'package:bean_count/data/repositories/account_repository.dart';
import 'package:bean_count/data/repositories/category_repository.dart';
import 'package:bean_count/main.dart';
import 'package:bean_count/theme/app_theme.dart';
import 'package:bean_count/widgets/quick_entry_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

/// 深色模式回归：不做 golden（贵且脆），只守住两件事——
/// 关键文字存在，且文字颜色在深色底上是浅色（不是黑字黑底）。
void main() {
  late AppDatabase db;

  setUp(() {
    db = AppDatabase(openInMemoryConnection());
  });

  tearDown(() async => db.close());

  double luminanceOf(WidgetTester tester, String text) {
    final paragraph = tester.renderObject<RenderParagraph>(find.text(text).first);
    final color = paragraph.text.style?.color;
    expect(color, isNotNull, reason: '「$text」应该有解析后的颜色');
    return color!.computeLuminance();
  }

  testWidgets('深色模式下四个 Tab 都能构建且文字是浅色', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.75;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
    addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);

    await tester.pumpWidget(BeanApp(database: db));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    for (final label in ['明细', '洞察', '资产', '设置']) {
      expect(find.text(label), findsWidgets, reason: '$label 应该存在');
    }

    // 明细页的大标题：深色底上必须是浅色字
    expect(luminanceOf(tester, '明细'), greaterThan(0.5));

    // 切到设置页，标题同样可读
    await tester.tap(find.text('设置').last);
    await tester.pumpAndSettle();
    expect(luminanceOf(tester, '设置'), greaterThan(0.5));
  });

  testWidgets('深色模式下记账面板可读', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.75;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final categoriesRepo = CategoryRepository(db);
    final accountsRepo = AccountRepository(db);
    await db.select(db.categories).get();
    final categories = await categoriesRepo.allCategories();
    final accounts = await accountsRepo.withBalances();

    await tester.pumpWidget(
      MaterialApp(
        theme: buildBeanTheme(Brightness.dark),
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () => showModalBottomSheet<void>(
                  context: context,
                  isScrollControlled: true,
                  builder: (_) => QuickEntrySheet(
                    categories: categories,
                    accounts: accounts,
                    onSubmit: (_) async => null,
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

    expect(find.text('记一笔'), findsOneWidget);
    // 金额（0.00）在深色底上要是浅色
    expect(luminanceOf(tester, '0.00'), greaterThan(0.5));
  });
}
