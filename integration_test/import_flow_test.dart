import 'dart:convert';
import 'dart:typed_data';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:bean_count/data/db/app_database.dart';
import 'package:bean_count/data/db/connection.dart';
import 'package:bean_count/data/repositories/account_repository.dart';
import 'package:bean_count/data/repositories/attachment_repository.dart';
import 'package:bean_count/data/repositories/category_repository.dart';
import 'package:bean_count/data/repositories/transaction_repository.dart';
import 'package:bean_count/pages/import_page.dart';
import 'package:bean_count/services/import/import_service.dart';
import 'package:bean_count/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

/// 真机/模拟器上的端到端：图片真的落到应用目录、交易真的进库、报告数字对得上。
///
/// 运行：flutter test integration_test/import_flow_test.dart -d emulator-5554
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('导入 zip：写库 + 图片落盘 + 报告', (tester) async {
    final db = AppDatabase(openInMemoryConnection());
    final categories = CategoryRepository(db);
    final accounts = AccountRepository(db);
    final transactions = TransactionRepository(db);
    final attachments = AttachmentRepository(db);
    final service = ImportService(
      db: db,
      categories: categories,
      accounts: accounts,
      transactions: transactions,
      attachments: attachments,
    );
    await db.select(db.transactions).get();

    final zipBytes = Uint8List.fromList(_buildZip());

    await tester.pumpWidget(
      MaterialApp(
        theme: buildBeanTheme(Brightness.light),
        home: ImportPage(
          service: service,
          initialBytes: zipBytes,
          initialName: 'BeeCount.zip',
        ),
      ),
    );
    await tester.pumpAndSettle();

    // 3 行数据：2 笔支出 + 1 笔转账（跳过），其中 1 笔带图
    expect(find.text('开始导入 2 笔'), findsOneWidget);

    await tester.tap(find.text('开始导入 2 笔'));
    await tester.pumpAndSettle();

    expect(find.text('成功'), findsOneWidget);
    expect(find.text('复制报告'), findsOneWidget);
    expect(await transactions.count(), 2);

    // 图片真的落在私有目录里
    final dir = await attachments.ensureReady();
    final files = dir.listSync().whereType<File>().toList();
    expect(files, hasLength(1));
    expect(files.single.lengthSync(), greaterThan(0));

    await db.close();
  });
}

List<int> _buildZip() {
  // 一张 1×1 的 PNG，够验证"写进去"
  final image = base64Decode(
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==',
  );
  final csv = utf8.encode(
    '类型,分类,金额,时间,备注,附件\n'
    '支出,餐饮,38.50,  2026-10-17 12:30:00  ,牛肉面,shot.png\n'
    '收入,工资,1200.00,  2026-10-16 10:00:00  ,兼职工资,\n'
    '转账,,500.00,  2026-10-15 09:00:00  ,还信用卡,\n',
  );

  final tar = Archive()
    ..addFile(ArchiveFile('images/shot.png', image.length, image));
  final tarBytes = TarEncoder().encode(tar);
  final gz = GZipEncoder().encode(tarBytes)!;

  final zip = Archive()
    ..addFile(ArchiveFile('beecount_20261017_000000.csv', csv.length, csv))
    ..addFile(
      ArchiveFile('beecount_attachments_1.tar.gz', gz.length, gz),
    );
  return ZipEncoder().encode(zip)!;
}
