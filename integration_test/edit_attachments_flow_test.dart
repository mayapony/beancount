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
import 'package:integration_test/integration_test.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// 真机/模拟器：详情页加图 → 计数变化 → 删图 → 计数与文件都减少。
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  final png = Uint8List.fromList(<int>[
    0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, //
    0x00, 0x00, 0x00, 0x0D, 0x49, 0x48, 0x44, 0x52,
    0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
    0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4,
    0x89, 0x00, 0x00, 0x00, 0x0A, 0x49, 0x44, 0x41,
    0x54, 0x78, 0x9C, 0x63, 0x00, 0x01, 0x00, 0x00,
    0x05, 0x00, 0x01, 0x0D, 0x0A, 0x2D, 0xB4, 0x00,
    0x00, 0x00, 0x00, 0x49, 0x45, 0x4E, 0x44, 0xAE,
    0x42, 0x60, 0x82,
  ]);

  testWidgets('详情页加图与删图', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.75;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final base = await getApplicationDocumentsDirectory();
    final dir = Directory(p.join(base.path, 'it_edit_attachments'));
    if (await dir.exists()) await dir.delete(recursive: true);

    final db = AppDatabase(openInMemoryConnection());
    final attachments = AttachmentRepository(db, directory: dir);
    final transactions = TransactionRepository(db, attachments: attachments);
    final categories = CategoryRepository(db);
    await db.select(db.categories).get();
    await attachments.ensureReady();

    final food = (await categories.findByName('餐饮', CategoryType.expense))!;
    final created = await transactions.create(
      NewTransaction(
        type: EntryType.expense,
        amountCents: 3850,
        categoryId: food.id,
        happenedAt: DateTime.now(),
        note: '可编辑图片',
      ),
    );
    final row = (await transactions.byId(created.transactionId))!;

    await tester.pumpWidget(
      MaterialApp(
        theme: buildBeanTheme(Brightness.light),
        home: TransactionDetailPage(
          row: row,
          repository: transactions,
          attachments: attachments,
          pickImage: (_) async => PickedImage(bytes: png, fileName: 'added.png'),
          categories: await categories.allCategories(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('图片 · 0'), findsOneWidget);
    await tester.tap(find.text('添加图片'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('从相册选择'));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('图片 · 1'), findsOneWidget);
    expect(dir.listSync().whereType<File>(), hasLength(1));

    // 删掉这张
    await tester.tap(find.byIcon(Icons.close_rounded).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('删除'));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('图片 · 1'), findsNothing);
    expect(await attachments.attachmentsOf(row.transaction.id), isEmpty);
    expect(dir.listSync().whereType<File>(), isEmpty);

    await db.close();
    if (await dir.exists()) await dir.delete(recursive: true);
  });
}
