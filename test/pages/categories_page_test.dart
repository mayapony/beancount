import 'package:bean_count/data/db/app_database.dart';
import 'package:bean_count/data/db/connection.dart';
import 'package:bean_count/data/db/enums.dart';
import 'package:bean_count/data/repositories/category_repository.dart';
import 'package:bean_count/data/repositories/transaction_repository.dart';
import 'package:bean_count/pages/categories_page.dart';
import 'package:bean_count/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late AppDatabase db;
  late CategoryRepository categories;
  late TransactionRepository transactions;

  setUp(() async {
    db = AppDatabase(openInMemoryConnection());
    categories = CategoryRepository(db);
    transactions = TransactionRepository(db);
    await db.select(db.categories).get();
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
        home: CategoriesPage(repository: categories),
      ),
    );
    await tester.pump();
    await tester.pump();
  }

  testWidgets('列出一级与二级分类，并显示使用笔数', (tester) async {
    final food = (await categories.findByName('餐饮', CategoryType.expense))!;
    await categories.ensure(
      name: '外卖',
      type: CategoryType.expense,
      parentId: food.id,
    );
    await transactions.create(
      NewTransaction(
        type: EntryType.expense,
        amountCents: 2000,
        categoryId: food.id,
        happenedAt: DateTime(2026, 10, 17, 9),
        note: '一笔',
      ),
    );

    await pumpPage(tester);

    expect(find.text('餐饮'), findsOneWidget);
    expect(find.text('外卖'), findsOneWidget);
    expect(find.text('1 笔'), findsWidgets);
    // 未使用的分类显示「未使用」
    expect(find.text('未使用'), findsWidgets);
  });

  testWidgets('新建二级分类后出现在父分类下', (tester) async {
    await pumpPage(tester);

    await tester.tap(find.byTooltip('新建分类'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), '维修');
    // 归属选「餐饮」
    await tester.tap(find.text('餐饮').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();

    expect(find.text('维修'), findsOneWidget);
    final created = await categories.findByName(
      '维修',
      CategoryType.expense,
      parentId: (await categories.findByName('餐饮', CategoryType.expense))!.id,
    );
    expect(created, isNotNull);
  });

  testWidgets('改名：重名给出提示且不写入', (tester) async {
    final transport =
        (await categories.findByName('交通', CategoryType.expense))!;
    await pumpPage(tester);

    await tester.tap(find.text('交通'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '餐饮');
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();

    expect(find.textContaining('已有一级分类「餐饮」'), findsOneWidget);
    expect((await categories.byId(transport.id))!.name, '交通');
  });

  testWidgets('上移改变分类顺序', (tester) async {
    final before = await categories.roots(CategoryType.expense);
    final second = before[1];

    await pumpPage(tester);
    await tester.tap(find.text(second.name));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('上移'));
    await tester.pumpAndSettle();

    final after = await categories.roots(CategoryType.expense);
    expect(after.first.id, second.id);
  });

  testWidgets('删除未使用的分类直接生效', (tester) async {
    final transport =
        (await categories.findByName('交通', CategoryType.expense))!;
    await pumpPage(tester);

    final row = find.ancestor(
      of: find.text('交通'),
      matching: find.byType(Row),
    );
    await tester.tap(
      find.descendant(of: row.first, matching: find.byTooltip('删除')),
    );
    await tester.pumpAndSettle();

    expect(find.text('交通'), findsNothing);
    expect(await categories.byId(transport.id), isNull);
  });

  testWidgets('删除被引用的分类：先迁移再删除', (tester) async {
    final food = (await categories.findByName('餐饮', CategoryType.expense))!;
    final target = (await categories.findByName('交通', CategoryType.expense))!;
    await transactions.create(
      NewTransaction(
        type: EntryType.expense,
        amountCents: 3850,
        categoryId: food.id,
        happenedAt: DateTime(2026, 10, 17, 12),
        note: '牛肉面',
      ),
    );

    await pumpPage(tester);

    final row = find.ancestor(
      of: find.text('餐饮'),
      matching: find.byType(Row),
    );
    await tester.tap(
      find.descendant(of: row.first, matching: find.byTooltip('删除')),
    );
    await tester.pumpAndSettle();

    // 迁移面板出现，列出同类型其它分类
    expect(find.text('迁移到'), findsOneWidget);
    await tester.tap(find.text('交通').last);
    await tester.pumpAndSettle();

    expect(await categories.byId(food.id), isNull);
    expect(await categories.transactionCount(target.id), 1);
    expect(await transactions.count(), 1, reason: '交易被迁移而不是删除');
  });
}
