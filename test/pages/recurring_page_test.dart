import 'package:bean_count/data/db/app_database.dart';
import 'package:bean_count/data/db/connection.dart';
import 'package:bean_count/data/db/enums.dart';
import 'package:bean_count/data/repositories/account_repository.dart';
import 'package:bean_count/data/repositories/category_repository.dart';
import 'package:bean_count/data/repositories/recurring_repository.dart';
import 'package:bean_count/pages/recurring_page.dart';
import 'package:bean_count/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late AppDatabase db;
  late RecurringRepository rules;
  late CategoryRepository categories;
  late AccountRepository accounts;

  setUp(() async {
    db = AppDatabase(openInMemoryConnection());
    rules = RecurringRepository(db);
    categories = CategoryRepository(db);
    accounts = AccountRepository(db);
    await db.select(db.categories).get();
  });

  tearDown(() async => db.close());

  Future<String> foodId() async =>
      (await categories.findByName('餐饮', CategoryType.expense))!.id;

  Future<void> pumpPage(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.75;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        theme: buildBeanTheme(Brightness.light),
        home: RecurringPage(
          rules: rules,
          categories: categories,
          accounts: accounts,
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
  }

  testWidgets('列出规则：标题、周期、金额与下次执行', (tester) async {
    await rules.create(
      type: EntryType.expense,
      amountCents: 250000,
      categoryId: await foodId(),
      note: '房租',
      dayOfMonth: 5,
      startYear: 2026,
      startMonth: 1,
    );

    await pumpPage(tester);

    expect(find.text('房租'), findsOneWidget);
    expect(find.textContaining('每月 5 日'), findsOneWidget);
    expect(find.textContaining('2,500.00'), findsOneWidget);
    expect(find.textContaining('下次'), findsOneWidget);
  });

  testWidgets('新建支出规则后出现在列表', (tester) async {
    await pumpPage(tester);

    await tester.tap(find.byTooltip('新建规则'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField).at(0), '99.00');
    await tester.tap(find.text('购物'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).at(1), '宽带费');
    await tester.tap(find.text('20'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();

    expect(find.text('宽带费'), findsOneWidget);
    final created = (await rules.all()).single;
    expect(created.amountCents, 9900);
    expect(created.dayOfMonth, 20);
    expect(created.note, '宽带费');
  });

  testWidgets('暂停规则后标记为已暂停', (tester) async {
    final rule = await rules.create(
      type: EntryType.expense,
      amountCents: 1000,
      categoryId: await foodId(),
      note: '会员',
      dayOfMonth: 1,
      startYear: 2026,
      startMonth: 1,
    );

    await pumpPage(tester);
    await tester.tap(find.text('会员'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('已启用'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();

    expect(find.text('已暂停'), findsWidgets);
    expect((await rules.byId(rule.id))!.enabled, isFalse);
  });

  testWidgets('删除规则后从列表消失', (tester) async {
    final rule = await rules.create(
      type: EntryType.expense,
      amountCents: 1000,
      categoryId: await foodId(),
      note: '会员',
      dayOfMonth: 1,
      startYear: 2026,
      startMonth: 1,
    );

    await pumpPage(tester);
    await tester.tap(find.text('会员'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('删除'));
    await tester.pumpAndSettle();

    expect(find.text('会员'), findsNothing);
    expect(await rules.byId(rule.id), isNull);
  });
}
