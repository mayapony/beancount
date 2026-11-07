import 'dart:io';

import 'package:bean_count/data/db/app_database.dart';
import 'package:bean_count/data/db/connection.dart';
import 'package:bean_count/data/db/enums.dart';
import 'package:bean_count/data/repositories/account_repository.dart';
import 'package:bean_count/data/repositories/attachment_repository.dart';
import 'package:bean_count/data/repositories/category_repository.dart';
import 'package:bean_count/data/repositories/transaction_repository.dart';
import 'package:bean_count/pages/auto_entries_page.dart';
import 'package:bean_count/pages/transaction_detail_page.dart';
import 'package:bean_count/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late AppDatabase db;
  late TransactionRepository repo;
  late CategoryRepository categories;
  late AccountRepository accounts;
  late AttachmentRepository attachments;
  late Directory tmp;

  setUp(() async {
    db = AppDatabase(openInMemoryConnection());
    categories = CategoryRepository(db);
    accounts = AccountRepository(db);
    tmp = await Directory.systemTemp.createTemp('bean_auto_list');
    attachments = AttachmentRepository(db, directory: tmp);
    repo = TransactionRepository(db, attachments: attachments);
    await db.select(db.transactions).get(); // 建库 + 种子
  });

  tearDown(() async {
    await db.close();
    if (await tmp.exists()) await tmp.delete(recursive: true);
  });

  Future<void> seedAuto({
    required int amountCents,
    required DateTime at,
    String note = '',
    String? sourcePackage,
    bool needsReview = false,
    String? sourceChannel,
  }) async {
    final category = (await categories.all(CategoryType.expense)).first;
    await repo.create(NewTransaction(
      type: EntryType.expense,
      amountCents: amountCents,
      categoryId: category.id,
      happenedAt: at,
      note: note,
      source: EntrySource.auto,
      sourcePackage: sourcePackage,
      sourceChannel: sourceChannel,
      needsReview: needsReview,
    ));
  }

  Future<void> pumpPage(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.75;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        theme: buildBeanTheme(Brightness.light),
        home: AutoEntriesPage(
          repository: repo,
          attachments: attachments,
          categories: await categories.allCategories(),
          accounts: await accounts.withBalances(),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
  }

  testWidgets('只展示自动记账，标题显示今天笔数', (tester) async {
    final now = DateTime.now();
    await seedAuto(amountCents: 1200, at: now, note: '今天午饭');
    await seedAuto(
      amountCents: 880,
      at: now.subtract(const Duration(days: 1)),
      note: '昨天晚饭',
    );
    // 手动账不应出现
    final category = (await categories.all(CategoryType.expense)).first;
    await repo.create(NewTransaction(
      type: EntryType.expense,
      amountCents: 500,
      categoryId: category.id,
      happenedAt: now,
      note: '手动记的一笔',
      source: EntrySource.manual,
    ));

    await pumpPage(tester);

    expect(find.text('今天 1 笔 · 点进详情可修改或删除'), findsOneWidget);
    expect(find.text('今天午饭'), findsOneWidget);
    expect(find.text('昨天晚饭'), findsOneWidget);
    expect(find.text('手动记的一笔'), findsNothing);
  });

  testWidgets('空列表显示空状态', (tester) async {
    await pumpPage(tester);
    expect(find.text('还没有自动记账'), findsOneWidget);
  });

  testWidgets('点进详情删除后返回列表即消失', (tester) async {
    await seedAuto(amountCents: 4500, at: DateTime.now(), note: '待删的自动账');

    await pumpPage(tester);
    expect(find.text('待删的自动账'), findsOneWidget);

    await tester.tap(find.text('待删的自动账'));
    await tester.pumpAndSettle();
    expect(find.byType(TransactionDetailPage), findsOneWidget);

    await tester.tap(find.text('删除这笔'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('删除'));
    await tester.pumpAndSettle();

    // 退回列表并刷新
    expect(find.byType(AutoEntriesPage), findsOneWidget);
    expect(find.text('待删的自动账'), findsNothing);
    expect(find.text('还没有自动记账'), findsOneWidget);
  });

  testWidgets('点进详情修改分类后返回列表刷新', (tester) async {
    await seedAuto(amountCents: 3850, at: DateTime.now(), note: '可改的自动账');

    await pumpPage(tester);
    await tester.tap(find.text('可改的自动账'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('编辑'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('交通'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('完成').last);
    await tester.pumpAndSettle();

    // 详情页里已经是新分类
    expect(find.text('交通'), findsWidgets);

    await tester.tap(find.byTooltip('返回'));
    await tester.pumpAndSettle();

    // 列表标题随分类变化：原备注仍在（备注优先于分类名）
    expect(find.text('可改的自动账'), findsOneWidget);
    final stored = await repo.recentAutoEntries();
    expect(stored.single.category?.name, '交通');
  });
  testWidgets('带来源应用的自动账显示应用名', (tester) async {
    await seedAuto(
      amountCents: 6900,
      at: DateTime.now(),
      note: '网易严选',
      sourcePackage: 'com.jingdong.app.mall',
    );

    await pumpPage(tester);

    expect(find.textContaining('来自 京东'), findsOneWidget);
  });

  testWidgets('没有来源应用时不显示来源字样', (tester) async {
    await seedAuto(amountCents: 1200, at: DateTime.now(), note: '午饭');

    await pumpPage(tester);

    expect(find.textContaining('来自'), findsNothing);
  });
  testWidgets('待人工处理的排在最前并可以补账户', (tester) async {
    final now = DateTime.now();
    final bank = await accounts.ensure(name: '招商银行');
    await seedAuto(amountCents: 1200, at: now, note: '正常一笔');
    await seedAuto(
      amountCents: 6900,
      at: now.subtract(const Duration(hours: 1)),
      note: '网易严选',
      sourcePackage: 'com.jingdong.app.mall',
      sourceChannel: '银行卡',
      needsReview: true,
    );

    await pumpPage(tester);

    // 待处理的那笔虽然更早，但排在第一位
    final rows = await repo.recentAutoEntries();
    expect(
      rows.firstWhere((r) => r.transaction.needsReview == true).transaction.note,
      '网易严选',
    );
    expect(find.text('待处理 · 选账户'), findsOneWidget);

    final pending = rows.firstWhere((r) => r.transaction.needsReview == true);
    await tester.tap(find.byKey(Key('auto-entry-assign-${pending.transaction.id}')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(Key('auto-entry-account-${bank.id}')));
    await tester.pumpAndSettle();

    final updated = (await repo.recentAutoEntries())
        .firstWhere((r) => r.transaction.id == pending.transaction.id);
    expect(updated.transaction.needsReview, isNull);
    expect(updated.transaction.accountId, bank.id);
    expect(find.text('待处理 · 选账户'), findsNothing);
  });
}