import 'dart:io';
import 'dart:typed_data';

import 'package:bean_count/data/db/app_database.dart';
import 'package:bean_count/data/db/connection.dart';
import 'package:bean_count/data/db/enums.dart';
import 'package:bean_count/data/repositories/attachment_repository.dart';
import 'package:bean_count/data/repositories/category_repository.dart';
import 'package:bean_count/data/repositories/transaction_repository.dart';
import 'package:bean_count/services/export/export_service.dart';
import 'package:bean_count/services/import/bee_count_archive.dart';
import 'package:bean_count/services/import/bee_count_csv.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late AppDatabase db;
  late TransactionRepository repo;
  late CategoryRepository categories;
  late AttachmentRepository attachments;
  late Directory tmp;
  late ExportService service;

  setUp(() async {
    db = AppDatabase(openInMemoryConnection());
    categories = CategoryRepository(db);
    tmp = await Directory.systemTemp.createTemp('bean_export_zip');
    attachments = AttachmentRepository(db, directory: tmp);
    repo = TransactionRepository(db, attachments: attachments);
    service = ExportService(
      transactions: repo,
      attachments: attachments,
      // 固定时间戳，断言文件名可预期
      clock: () => DateTime(2026, 10, 18, 1, 15, 0),
    );
    await db.select(db.transactions).get();
  });

  tearDown(() async {
    await db.close();
    if (await tmp.exists()) await tmp.delete(recursive: true);
  });

  test('buildCsv 的文件名带时间戳、图片数为 0', () async {
    await repo.create(
      NewTransaction(
        type: EntryType.expense,
        amountCents: 1000,
        categoryId: (await categories.findByName('餐饮', CategoryType.expense))!
            .id,
        happenedAt: DateTime(2026, 10, 17, 9),
      ),
    );

    final csv = await service.buildCsv();
    expect(csv.fileName, 'beecount_20261018_011500.csv');
    expect(csv.entryCount, 1);
    expect(csv.imageCount, 0);
    expect(csv.bytes.length, greaterThan(0));
  });

  test('buildBackup 的 zip 内含 csv 与附件包，且能被导入端解析', () async {
    final category =
        (await categories.findByName('餐饮', CategoryType.expense))!;
    final withImage = await repo.create(
      NewTransaction(
        type: EntryType.expense,
        amountCents: 3850,
        categoryId: category.id,
        happenedAt: DateTime(2026, 10, 17, 12, 30),
        note: '带图',
      ),
    );
    await repo.create(
      NewTransaction(
        type: EntryType.expense,
        amountCents: 1500,
        categoryId: category.id,
        happenedAt: DateTime(2026, 10, 17, 18),
        note: '没图',
      ),
    );
    await attachments.ensureReady();
    final imageBytes = Uint8List.fromList(<int>[9, 8, 7, 6, 5]);
    await attachments.add(
      transactionId: withImage.transactionId,
      bytes: imageBytes,
      fileName: 'receipt.png',
    );

    final backup = await service.buildBackup();
    expect(backup.fileName, 'beancount_backup_20261018_011500.zip');
    expect(backup.entryCount, 2);
    expect(backup.imageCount, 1);
    expect(backup.readableSize, contains('B'), reason: '小包按字节显示');

    // 用导入端的解析器读回来
    final extracted = extractBeeCountExport(backup.bytes, name: backup.fileName);
    expect(extracted.fatal, isNull);
    expect(extracted.attachments, hasLength(1));
    expect(extracted.attachments.single.fileName, 'receipt.png');
    expect(extracted.attachments.single.bytes, imageBytes);

    final parsed = parseBeeCountCsv(extracted.csvBytes);
    expect(parsed.fatal, isNull);
    expect(parsed.rows, hasLength(2));
    expect(parsed.rows.first.attachments, ['receipt.png']);
    expect(parsed.rows.last.attachments, isEmpty);
  });

  test('共享图片在备份里只出现一份', () async {
    final category =
        (await categories.findByName('餐饮', CategoryType.expense))!;
    final a = await repo.create(
      NewTransaction(
        type: EntryType.expense,
        amountCents: 1000,
        categoryId: category.id,
        happenedAt: DateTime(2026, 10, 17, 9),
        note: 'A',
      ),
    );
    final b = await repo.create(
      NewTransaction(
        type: EntryType.expense,
        amountCents: 2000,
        categoryId: category.id,
        happenedAt: DateTime(2026, 10, 17, 10),
        note: 'B',
      ),
    );
    await attachments.ensureReady();
    await attachments.add(
      transactionId: a.transactionId,
      bytes: Uint8List.fromList(<int>[1, 2, 3]),
      fileName: 'shared.png',
    );
    await attachments.add(
      transactionId: b.transactionId,
      bytes: Uint8List.fromList(<int>[1, 2, 3]),
      fileName: 'shared.png',
    );

    final backup = await service.buildBackup();
    expect(backup.imageCount, 1);

    final extracted = extractBeeCountExport(backup.bytes);
    expect(extracted.attachments, hasLength(1));
    final parsed = parseBeeCountCsv(extracted.csvBytes);
    expect(
      parsed.rows.every((r) => r.attachments.length == 1),
      isTrue,
      reason: '两笔账都指向同一个文件名',
    );
  });

  test('空账本的备份也是合法 zip（附件包为空而非缺失）', () async {
    final backup = await service.buildBackup();
    expect(backup.entryCount, 0);
    expect(backup.imageCount, 0);

    final extracted = extractBeeCountExport(backup.bytes);
    expect(extracted.fatal, isNull);
    expect(extracted.attachments, isEmpty);
    final parsed = parseBeeCountCsv(extracted.csvBytes);
    expect(parsed.fatal, isNull);
    expect(parsed.rows, isEmpty);
  });

  test('可读大小按 1024 进制一档一档进位', () {
    ExportFile of(int size) => ExportFile(
          fileName: 'x',
          bytes: Uint8List(size),
          entryCount: 0,
          imageCount: 0,
        );
    expect(of(12).readableSize, '12 B');
    expect(of(2048).readableSize, '2.0 KB');
    expect(of(18 * 1024 * 1024).readableSize, '18 MB');
  });
}
