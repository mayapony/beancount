import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:bean_count/data/db/app_database.dart';
import 'package:bean_count/data/db/connection.dart';
import 'package:bean_count/data/db/enums.dart';
import 'package:bean_count/data/repositories/account_repository.dart';
import 'package:bean_count/data/repositories/attachment_repository.dart';
import 'package:bean_count/data/repositories/category_repository.dart';
import 'package:bean_count/data/repositories/transaction_repository.dart';
import 'package:bean_count/services/export/export_service.dart';
import 'package:bean_count/services/import/bee_count_archive.dart';
import 'package:bean_count/services/import/bee_count_csv.dart';
import 'package:bean_count/services/import/import_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// 真机/模拟器：导出备份 → 写盘 → 在空账本上导入回来，笔数与图片一致。
///
/// 运行：flutter test integration_test/export_roundtrip_test.dart -d emulator-5554
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('完整备份往返：导出 → 落盘 → 导入，笔数与图片对得上', (tester) async {
    final base = await getApplicationDocumentsDirectory();
    final sourceDir = Directory(p.join(base.path, 'it_export_src'));
    final targetDir = Directory(p.join(base.path, 'it_export_dst'));
    for (final dir in [sourceDir, targetDir]) {
      if (await dir.exists()) await dir.delete(recursive: true);
      await dir.create(recursive: true);
    }

    // ── 源账本：3 笔账、2 张图（其中一张被两笔共用）
    final source = AppDatabase(openInMemoryConnection());
    final sourceCategories = CategoryRepository(source);
    final sourceAttachments = AttachmentRepository(source, directory: sourceDir);
    final sourceRepo =
        TransactionRepository(source, attachments: sourceAttachments);
    await source.select(source.transactions).get();

    final food = (await sourceCategories.findByName('餐饮', CategoryType.expense))!;
    final first = await sourceRepo.create(
      NewTransaction(
        type: EntryType.expense,
        amountCents: 3850,
        categoryId: food.id,
        happenedAt: DateTime(2026, 10, 17, 12, 30),
        note: '带图一',
        tags: ['出差'],
      ),
    );
    await sourceRepo.create(
      NewTransaction(
        type: EntryType.expense,
        amountCents: 1500,
        categoryId: food.id,
        happenedAt: DateTime(2026, 10, 17, 19),
        note: '共用图',
      ),
    );
    await sourceRepo.create(
      NewTransaction(
        type: EntryType.income,
        amountCents: 1451901,
        categoryId:
            (await sourceCategories.findByName('工资', CategoryType.income))!.id,
        happenedAt: DateTime(2026, 10, 16, 10),
        note: '工资',
      ),
    );

    await sourceAttachments.ensureReady();
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
    await sourceAttachments.add(
      transactionId: first.transactionId,
      bytes: png,
      fileName: 'sha_aaa.png',
    );
    await sourceAttachments.add(
      transactionId: first.transactionId,
      bytes: Uint8List.fromList(utf8.encode('second-image')),
      fileName: 'sha_bbb.png',
      sortOrder: 1,
    );

    final exporter = ExportService(
      transactions: sourceRepo,
      attachments: sourceAttachments,
    );
    final backup = await exporter.buildBackup();
    expect(backup.entryCount, 3);
    expect(backup.imageCount, 2);

    // ── 真的写到磁盘（模拟 saveFile 落地的字节）
    final file = File(p.join(base.path, backup.fileName));
    await file.writeAsBytes(backup.bytes, flush: true);
    expect(await file.exists(), isTrue);
    final readBack = await file.readAsBytes();

    // ── 目标账本：导入回来
    final target = AppDatabase(openInMemoryConnection());
    final targetAttachments =
        AttachmentRepository(target, directory: targetDir);
    final targetTransactions =
        TransactionRepository(target, attachments: targetAttachments);
    final importer = ImportService(
      db: target,
      categories: CategoryRepository(target),
      accounts: AccountRepository(target),
      transactions: targetTransactions,
      attachments: targetAttachments,
    );
    await target.select(target.transactions).get();

    final extracted = extractBeeCountExport(readBack, name: backup.fileName);
    expect(extracted.fatal, isNull);
    final parsed = parseBeeCountCsv(extracted.csvBytes);
    expect(parsed.fatal, isNull);
    expect(parsed.rows, hasLength(3));

    final plan = await planImport(
      service: importer,
      parsed: parsed,
      attachmentSizes: {
        for (final attachment in extracted.attachments)
          attachment.fileName: attachment.bytes.length,
      },
    );
    final report = await importer.apply(
      plan,
      attachments: {
        for (final attachment in extracted.attachments)
          attachment.fileName: attachment,
      },
    );

    expect(report.inserted, 3);
    expect(report.failed, 0);
    expect(await targetTransactions.count(), 3);

    final targetDirFiles = await targetAttachments.allFiles();
    expect(targetDirFiles, hasLength(2), reason: '两张图都还原了');

    final rows = await targetTransactions.exportRows();
    expect(rows, hasLength(3));
    final restored = rows.firstWhere((r) => r.transaction.note == '带图一');
    expect(restored.attachmentNames, hasLength(2));
    expect(restored.tags, ['出差']);
    expect(restored.transaction.amountCents, 3850);

    await source.close();
    await target.close();
    await file.delete();
    if (await sourceDir.exists()) await sourceDir.delete(recursive: true);
    if (await targetDir.exists()) await targetDir.delete(recursive: true);
  });
}
