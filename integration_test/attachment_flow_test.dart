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
import 'package:bean_count/services/entry/entry_writer.dart';
import 'package:bean_count/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// 真机/模拟器：选图提交后文件真的落盘、详情能显示，删掉这笔文件被回收。
///
/// 运行：flutter test integration_test/attachment_flow_test.dart -d emulator-5554
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  // 1×1 透明 PNG：足够验证"能写、能解码、能删"
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

  testWidgets('带图记账：文件落盘、详情可见、删除后回收', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.75;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final base = await getApplicationDocumentsDirectory();
    final dir = Directory(p.join(base.path, 'it_attachments_flow'));
    if (await dir.exists()) await dir.delete(recursive: true);

    final db = AppDatabase(openInMemoryConnection());
    final categories = CategoryRepository(db);
    final attachments = AttachmentRepository(db, directory: dir);
    final transactions = TransactionRepository(db, attachments: attachments);
    final writer = EntryWriter(transactions: transactions, attachments: attachments);
    await db.select(db.categories).get();
    await attachments.ensureReady();

    final food = (await categories.findByName('餐饮', CategoryType.expense))!;
    final result = await writer.submit(
      type: EntryType.expense,
      amountCents: 3850,
      categoryId: food.id,
      happenedAt: DateTime.now(),
      note: '带图记账',
      images: [
        PickedImage(bytes: png, fileName: 'shot_1.png'),
        PickedImage(bytes: png, fileName: 'shot_2.png'),
      ],
    );
    expect(result.inserted, isTrue);

    final files = dir.listSync().whereType<File>().toList();
    expect(files, hasLength(2), reason: '两张图都落盘了');
    expect(files.every((f) => f.lengthSync() > 0), isTrue);

    // 详情页能显示这两张图
    final row = (await transactions.byId(result.transactionId))!;
    await tester.pumpWidget(
      MaterialApp(
        theme: buildBeanTheme(Brightness.light),
        home: TransactionDetailPage(
          row: row,
          repository: transactions,
          attachments: attachments,
          categories: await categories.allCategories(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.pump(const Duration(milliseconds: 200));

    expect(find.textContaining('图片 · 2'), findsOneWidget);

    // 删除这笔：两张图都被回收
    await transactions.delete(result.transactionId);
    expect(await transactions.byId(result.transactionId), isNull);
    expect(dir.listSync().whereType<File>(), isEmpty);

    await db.close();
    if (await dir.exists()) await dir.delete(recursive: true);
  });
}
