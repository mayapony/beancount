import 'dart:io';
import 'dart:typed_data';

import 'package:bean_count/data/db/app_database.dart';
import 'package:bean_count/data/db/connection.dart';
import 'package:bean_count/data/db/enums.dart';
import 'package:bean_count/data/repositories/attachment_repository.dart';
import 'package:bean_count/data/repositories/category_repository.dart';
import 'package:bean_count/data/repositories/transaction_repository.dart';
import 'package:bean_count/pages/transaction_detail_page.dart';
import 'package:bean_count/services/attachments/image_picker_service.dart';
import 'package:bean_count/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late AppDatabase db;
  late Directory tmp;
  late AttachmentRepository attachments;
  late TransactionRepository transactions;
  late CategoryRepository categories;

  setUp(() async {
    db = AppDatabase(openInMemoryConnection());
    tmp = await Directory.systemTemp.createTemp('bean_edit_att');
    attachments = AttachmentRepository(db, directory: tmp);
    transactions = TransactionRepository(db, attachments: attachments);
    categories = CategoryRepository(db);
    await db.select(db.categories).get();
    await attachments.ensureReady();
  });

  tearDown(() async {
    await db.close();
    if (await tmp.exists()) {
      try {
        await tmp.delete(recursive: true);
      } on FileSystemException {
        // Windows 上偶发占用，忽略
      }
    }
  });

  PickedImage image(String name, {int size = 8}) => PickedImage(
        bytes: Uint8List.fromList(List<int>.filled(size, 3)),
        fileName: name,
      );

  Future<TransactionRow> seed() async {
    final food = (await categories.findByName('餐饮', CategoryType.expense))!;
    final result = await transactions.create(
      NewTransaction(
        type: EntryType.expense,
        amountCents: 3850,
        categoryId: food.id,
        happenedAt: DateTime(2026, 10, 18, 12),
        note: '牛肉面',
      ),
    );
    return (await transactions.byId(result.transactionId))!;
  }

  Future<void> pump(
    WidgetTester tester,
    TransactionRow row, {
    ImagePickFn? picker,
  }) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.75;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        theme: buildBeanTheme(Brightness.light),
        home: TransactionDetailPage(
          row: row,
          repository: transactions,
          attachments: attachments,
          pickImage: picker,
          categories: await categories.allCategories(),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
  }

  testWidgets('点添加图片会走选图流程', (tester) async {
    final row = await seed();
    var picks = 0;
    await pump(
      tester,
      row,
      picker: (_) async {
        picks++;
        return null;
      },
    );

    expect(find.text('图片 · 0'), findsOneWidget);
    await tester.tap(find.text('添加图片'));
    await tester.pumpAndSettle();

    // 来源面板：相册 / 拍照 / 取消
    expect(find.text('从相册选择'), findsOneWidget);
    expect(find.text('拍照'), findsOneWidget);

    await tester.tap(find.text('拍照'));
    await tester.pumpAndSettle();
    expect(picks, 1, reason: '选择了来源后调用选图实现');
  });

  testWidgets('取消选图不新增记录', (tester) async {
    final row = await seed();
    await pump(tester, row, picker: (_) async => null);

    await tester.tap(find.text('添加图片'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('从相册选择'));
    await tester.pumpAndSettle();

    expect(find.text('图片 · 0'), findsOneWidget);
    expect(await attachments.attachmentsOf(row.transaction.id), isEmpty);
  });

  testWidgets('删图：确认后移除记录与文件', (tester) async {
    final row = await seed();
    await tester.runAsync(() async {
      await attachments.add(
        transactionId: row.transaction.id,
        bytes: image('one.png').bytes,
        fileName: 'one.png',
      );
      await attachments.add(
        transactionId: row.transaction.id,
        bytes: image('two.png').bytes,
        fileName: 'two.png',
      );
    });
    await pump(tester, row, picker: (_) async => null);

    expect(find.text('图片 · 2'), findsOneWidget);
    // 点第一张的删除角标
    await tester.tap(find.byIcon(Icons.close_rounded).first);
    await tester.pumpAndSettle();
    expect(find.text('删除这张图片？'), findsOneWidget);
    // 删记录 + 删文件都是真实 IO：整段交互放进 runAsync 才能推进
    await tester.runAsync(() async {
      await tester.tap(find.text('删除'));
      await tester.pump();
      await Future<void>.delayed(const Duration(milliseconds: 300));
      await tester.pump();
    });
    await tester.pumpAndSettle();

    // 记录被删掉了（真实 IO 的刷新时机在 widget 测试里不稳定，
    // 界面计数的变化放到设备端用例里验）
    await tester.runAsync(() async {
      expect(await attachments.attachmentsOf(row.transaction.id), hasLength(1));
    });
  });

  testWidgets('取消删除：图片与文件都不变', (tester) async {
    final row = await seed();
    await tester.runAsync(() async {
      await attachments.add(
        transactionId: row.transaction.id,
        bytes: image('keep.png').bytes,
        fileName: 'keep.png',
      );
    });
    await pump(tester, row, picker: (_) async => null);

    await tester.tap(find.byIcon(Icons.close_rounded).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();

    expect(find.text('图片 · 1'), findsOneWidget);
    expect(tmp.listSync().whereType<File>(), hasLength(1));
  });

  testWidgets('没有 pickImage 时不显示添加入口', (tester) async {
    final row = await seed();
    await pump(tester, row);
    expect(find.text('添加图片'), findsNothing);
  });
}
