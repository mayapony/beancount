import 'dart:io';
import 'dart:typed_data';

import 'package:bean_count/data/db/app_database.dart';
import 'package:bean_count/data/db/connection.dart';
import 'package:bean_count/data/db/enums.dart';
import 'package:bean_count/data/repositories/account_repository.dart';
import 'package:bean_count/data/repositories/attachment_repository.dart';
import 'package:bean_count/data/repositories/category_repository.dart';
import 'package:bean_count/data/repositories/transaction_repository.dart';
import 'package:bean_count/pages/transaction_detail_page.dart';
import 'package:bean_count/theme/app_theme.dart';
import 'package:bean_count/widgets/common.dart';
import 'package:bean_count/widgets/quick_entry_sheet.dart';
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
    tmp = await Directory.systemTemp.createTemp('bean_detail');
    attachments = AttachmentRepository(db, directory: tmp);
    repo = TransactionRepository(db, attachments: attachments);
    await db.select(db.transactions).get(); // 建库 + 种子
  });

  tearDown(() async {
    await db.close();
    if (await tmp.exists()) await tmp.delete(recursive: true);
  });

  Future<void> pumpDetail(WidgetTester tester, String id) async {
    // 详情页与记账面板都按手机尺寸设计，默认的 800×600 会把按钮挤出屏幕
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.75;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final row = await repo.byId(id);
    expect(row, isNotNull, reason: '前置：交易要存在');
    await tester.pumpWidget(
      MaterialApp(
        theme: buildBeanTheme(Brightness.light),
        home: TransactionDetailPage(
          row: row!,
          repository: repo,
          attachments: attachments,
          categories: await categories.allCategories(),
          accounts: await accounts.withBalances(),
        ),
      ),
    );
    // 页面在 initState 里补标签与图片，给两帧让它落定
    await tester.pump();
    await tester.pump();
  }

  testWidgets('展示金额、分类、账户、时间、备注与标签', (tester) async {
    final account = (await accounts.all()).first;
    final created = await repo.create(
      NewTransaction(
        type: EntryType.expense,
        amountCents: 3850,
        categoryId: (await categories.findByName('餐饮', CategoryType.expense))!
            .id,
        happenedAt: DateTime(2026, 10, 17, 12, 30),
        accountId: account.id,
        note: '牛肉面',
        tags: ['出差', '报销'],
      ),
    );

    await pumpDetail(tester, created.transactionId);

    expect(find.text('-38.50'), findsOneWidget);
    expect(find.text('餐饮'), findsWidgets);
    expect(find.text(account.name), findsOneWidget);
    expect(find.text('牛肉面'), findsOneWidget);
    expect(find.text('#出差'), findsOneWidget);
    expect(find.text('#报销'), findsOneWidget);
    expect(find.textContaining('12:30'), findsOneWidget);
  });

  testWidgets('编辑：改分类后保存，详情与库里的数据一起变', (tester) async {
    final created = await repo.create(
      NewTransaction(
        type: EntryType.expense,
        amountCents: 3850,
        categoryId: (await categories.findByName('餐饮', CategoryType.expense))!
            .id,
        happenedAt: DateTime(2026, 10, 17, 12, 30),
        note: '牛肉面',
      ),
    );

    await pumpDetail(tester, created.transactionId);
    expect(find.text('餐饮'), findsWidgets);

    await tester.tap(find.text('编辑'));
    await tester.pumpAndSettle();
    expect(find.text('编辑一笔'), findsOneWidget);

    // 换个分类：点网格里的「交通」
    await tester.tap(find.text('交通'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('完成').last);
    await tester.pumpAndSettle();

    // 详情页已刷新
    expect(find.text('交通'), findsWidgets);
    expect(find.text('餐饮'), findsNothing);

    // 库里也是新值
    final stored = await repo.byId(created.transactionId);
    expect(stored!.category?.name, '交通');
    expect(stored.amountCents, 3850);
  });

  testWidgets('编辑撞去重键：面板保持打开并提示，数据不变', (tester) async {
    final food = (await categories.findByName('餐饮', CategoryType.expense))!.id;
    await repo.create(
      NewTransaction(
        type: EntryType.expense,
        amountCents: 3850,
        categoryId: food,
        happenedAt: DateTime(2026, 10, 17, 12, 30),
        note: '聚餐',
      ),
    );
    final second = await repo.create(
      NewTransaction(
        type: EntryType.expense,
        amountCents: 3850,
        categoryId: food,
        happenedAt: DateTime(2026, 10, 17, 12, 30),
        note: '加班餐',
      ),
    );

    await pumpDetail(tester, second.transactionId);
    await tester.tap(find.text('编辑'));
    await tester.pumpAndSettle();

    // 把备注改成和第一笔一样 → 时间/金额/备注全同 → 撞键
    await tester.tap(find.descendant(
      of: find.byType(QuickEntrySheet),
      matching: find.textContaining('加班餐'),
    ));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField), '聚餐');
    await tester.tap(find.text('确定'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('完成').last);
    await tester.pumpAndSettle();

    expect(find.text('已存在相同时间、金额与备注的记录'), findsOneWidget);
    expect(find.text('编辑一笔'), findsOneWidget, reason: '面板保持打开');

    final stored = await repo.byId(second.transactionId);
    expect(stored!.transaction.note, '加班餐');
    expect(await repo.count(), 2);
  });

  testWidgets('无图不出现图片区，无账户不显示账户一行', (tester) async {
    final created = await repo.create(
      NewTransaction(
        type: EntryType.expense,
        amountCents: 1200,
        categoryId: (await categories.findByName('餐饮', CategoryType.expense))!
            .id,
        happenedAt: DateTime(2026, 10, 17, 8),
      ),
    );

    await pumpDetail(tester, created.transactionId);

    expect(find.byType(Image), findsNothing);
    expect(find.text('账户'), findsNothing);
    expect(find.text('备注'), findsNothing);
  });

  /// 有多步真实异步（DB / 文件）时 pumpAndSettle 等不到，手动多推几帧。
  Future<void> pumpFrames(WidgetTester tester) async {
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 40));
    }
  }

  testWidgets('删除：取消不删，确认后删除并退回上一页', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.75;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final created = await repo.create(
      NewTransaction(
        type: EntryType.expense,
        amountCents: 4500,
        categoryId: (await categories.findByName('餐饮', CategoryType.expense))!
            .id,
        happenedAt: DateTime(2026, 10, 17, 19),
        note: '晚饭',
      ),
    );

    // 用宿主页面 push 详情，才能验证「删除后退回上一页」
    await tester.pumpWidget(
      MaterialApp(
        theme: buildBeanTheme(Brightness.light),
        home: Scaffold(
          body: Builder(
            builder: (context) => Center(
              child: TextButton(
                onPressed: () async {
                  final row = await repo.byId(created.transactionId);
                  final cats = await categories.allCategories();
                  final accs = await accounts.withBalances();
                  if (!context.mounted) return;
                  await Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => TransactionDetailPage(
                        row: row!,
                        repository: repo,
                        attachments: attachments,
                        categories: cats,
                        accounts: accs,
                      ),
                    ),
                  );
                },
                child: const Text('打开'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('打开'));
    await pumpFrames(tester);
    expect(find.byType(TransactionDetailPage), findsOneWidget);

    // 取消：记录仍在
    await tester.tap(find.text('删除这笔'));
    await pumpFrames(tester);
    expect(find.text('删除这笔？'), findsOneWidget);
    expect(find.textContaining('45.00'), findsWidgets);
    await tester.tap(find.text('取消'));
    await pumpFrames(tester);
    expect(await repo.byId(created.transactionId), isNotNull);

    // 确认：删掉并回到宿主页
    await tester.tap(find.text('删除这笔'));
    await pumpFrames(tester);
    await tester.tap(find.text('删除'));
    await tester.pumpAndSettle();

    expect(await repo.byId(created.transactionId), isNull);
    expect(find.byType(TransactionDetailPage), findsNothing);
    expect(find.text('打开'), findsOneWidget);
  });

  testWidgets('删除最后一笔引用时，图片文件被回收（真实异步路径）', (tester) async {
    final created = await repo.create(
      NewTransaction(
        type: EntryType.expense,
        amountCents: 1200,
        categoryId: (await categories.findByName('餐饮', CategoryType.expense))!
            .id,
        happenedAt: DateTime(2026, 10, 17, 8),
        note: '带图',
      ),
    );
    // 文件删除是真实 IO：必须在 runAsync 里跑，否则 widget test 的假时钟会挂住
    await tester.runAsync(() async {
      await attachments.ensureReady();
      await attachments.add(
        transactionId: created.transactionId,
        bytes: Uint8List.fromList(<int>[1, 2, 3, 4]),
        fileName: 'only.png',
      );
      expect(File('${tmp.path}/only.png').existsSync(), isTrue);
      await repo.delete(created.transactionId);
    });

    expect(await repo.byId(created.transactionId), isNull);
    expect(
      File('${tmp.path}/only.png').existsSync(),
      isFalse,
      reason: '最后一条引用被删，文件要回收',
    );
  });

  testWidgets('有图时显示缩略图，数量写进标题', (tester) async {
    final created = await repo.create(
      NewTransaction(
        type: EntryType.expense,
        amountCents: 9900,
        categoryId: (await categories.findByName('购物', CategoryType.expense))!
            .id,
        happenedAt: DateTime(2026, 10, 17, 15),
        note: '带两张图',
      ),
    );
    await tester.runAsync(() async {
      await attachments.ensureReady();
      // 两张极小的 PNG，内容不重要，能落盘即可
      final bytes = Uint8List.fromList(<int>[0x89, 0x50, 0x4E, 0x47, 0, 0, 0, 0]);
      await attachments.add(
        transactionId: created.transactionId,
        bytes: bytes,
        fileName: 'a.png',
      );
      await attachments.add(
        transactionId: created.transactionId,
        bytes: Uint8List.fromList(<int>[0x89, 0x50, 0x4E, 0x48, 0, 0, 0, 0]),
        fileName: 'b.png',
        sortOrder: 1,
      );
    });

    await pumpDetail(tester, created.transactionId);

    expect(find.text('图片 · 2'), findsOneWidget);
    // 坏图会落到 errorBuilder 里的图标，但容器还在
    expect(find.byType(ClipRRect), findsWidgets);
  });

  testWidgets('空图片列表不渲染「图片 ·」标题', (tester) async {
    final created = await repo.create(
      NewTransaction(
        type: EntryType.income,
        amountCents: 500000,
        categoryId: (await categories.findByName('工资', CategoryType.income))!.id,
        happenedAt: DateTime(2026, 10, 10, 9),
        note: '发工资',
      ),
    );

    await pumpDetail(tester, created.transactionId);

    expect(find.textContaining('图片 ·'), findsNothing);
    expect(find.text('+5,000.00'), findsOneWidget);
    expect(find.text('收入'), findsOneWidget);
    expect(find.byType(BeanCard), findsWidgets);
  });

  testWidgets('转账详情：显示从/到、无分类行、金额不带符号', (tester) async {
    final from = (await accounts.all()).first;
    final to = await accounts.ensure(name: '支付宝');
    final created = await repo.create(
      NewTransaction(
        type: EntryType.transfer,
        amountCents: 50000,
        accountId: from.id,
        toAccountId: to.id,
        happenedAt: DateTime(2026, 10, 18, 12),
        note: '还信用卡',
      ),
    );

    await pumpDetail(tester, created.transactionId);

    expect(find.text('从'), findsOneWidget);
    expect(find.text('到'), findsOneWidget);
    expect(find.text(from.name), findsWidgets);
    expect(find.text(to.name), findsWidgets);
    expect(find.text('分类'), findsNothing);
    expect(find.text('500.00'), findsOneWidget);
    expect(find.text('-500.00'), findsNothing, reason: '转账不带符号');
    expect(find.textContaining('→'), findsWidgets);
  });

  testWidgets('删除转账后两端余额还原', (tester) async {
    final from = (await accounts.all()).first;
    final to = await accounts.ensure(name: '支付宝');
    // 记账前的基准余额
    final baseline = await accounts.withBalances();
    final created = await repo.create(
      NewTransaction(
        type: EntryType.transfer,
        amountCents: 50000,
        accountId: from.id,
        toAccountId: to.id,
        happenedAt: DateTime(2026, 10, 18, 12),
        note: '还信用卡',
      ),
    );

    await pumpDetail(tester, created.transactionId);
    await tester.tap(find.text('删除这笔'));
    await pumpFrames(tester);
    await tester.tap(find.text('删除'));
    await tester.pumpAndSettle();

    expect(await repo.byId(created.transactionId), isNull);
    final after = await accounts.withBalances();
    for (final id in [from.id, to.id]) {
      expect(
        after.firstWhere((b) => b.account.id == id).balanceCents,
        baseline.firstWhere((b) => b.account.id == id).balanceCents,
        reason: '删除后余额应回到转账前的值',
      );
    }
  });
}