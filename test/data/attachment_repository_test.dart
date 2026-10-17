import 'dart:io';
import 'dart:typed_data';

import 'package:bean_count/data/db/app_database.dart';
import 'package:bean_count/data/db/connection.dart';
import 'package:bean_count/data/db/enums.dart';
import 'package:bean_count/data/repositories/attachment_repository.dart';
import 'package:bean_count/data/repositories/category_repository.dart';
import 'package:bean_count/data/repositories/transaction_repository.dart';
import 'package:flutter_test/flutter_test.dart';

/// 1×1 的 PNG（67 字节），足够验证"写进去—读出来—删干净"。
final Uint8List _png = Uint8List.fromList(<int>[
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

void main() {
  late AppDatabase db;
  late AttachmentRepository repo;
  late TransactionRepository transactions;
  late CategoryRepository categories;
  late Directory tmp;

  setUp(() async {
    db = AppDatabase(openInMemoryConnection());
    tmp = await Directory.systemTemp.createTemp('bean_attachments');
    repo = AttachmentRepository(db, directory: tmp);
    transactions = TransactionRepository(db);
    categories = CategoryRepository(db);
    await db.select(db.transactions).get(); // 建库 + 种子
  });

  tearDown(() async {
    await db.close();
    if (await tmp.exists()) await tmp.delete(recursive: true);
  });

  Future<String> newTransaction({String note = '带图的一笔'}) async {
    final food = await categories.findByName('餐饮', CategoryType.expense);
    final result = await transactions.create(
      NewTransaction(
        type: EntryType.expense,
        amountCents: 1000,
        categoryId: food!.id,
        happenedAt: DateTime(2026, 10, 17, 12),
        note: note,
      ),
    );
    return result.transactionId;
  }

  test('写两张图后能读回，文件落在目录里', () async {
    final txId = await newTransaction();

    await repo.add(
      transactionId: txId,
      bytes: _png,
      fileName: 'sha_a.png',
      originalName: 'Screenshot_a.png',
    );
    await repo.add(
      transactionId: txId,
      bytes: _png,
      fileName: 'sha_b.png',
      sortOrder: 1,
    );

    final rows = await repo.attachmentsOf(txId);
    expect(rows, hasLength(2));
    expect(rows.first.fileName, 'sha_a.png');
    expect(rows.first.originalName, 'Screenshot_a.png');
    expect(rows.first.fileSize, _png.length);
    expect(repo.fileFor('sha_a.png')!.existsSync(), isTrue);
  });

  test('两笔交易共用同一张图：删一笔文件仍在，删最后一笔文件消失', () async {
    final a = await newTransaction(note: 'A');
    final b = await newTransaction(note: 'B');

    final attA = await repo.add(
      transactionId: a,
      bytes: _png,
      fileName: 'sha_shared.png',
    );
    await repo.add(
      transactionId: b,
      bytes: _png,
      fileName: 'sha_shared.png',
    );

    // 只存了一份文件
    final files = tmp.listSync().whereType<File>().toList();
    expect(files, hasLength(1));

    await repo.remove(attA.id);
    expect(await repo.attachmentsOf(a), isEmpty);
    expect(repo.fileFor('sha_shared.png')!.existsSync(), isTrue,
        reason: '另一笔还在用这张图');

    final remaining = (await repo.attachmentsOf(b)).single;
    await repo.remove(remaining.id);
    expect(repo.fileFor('sha_shared.png')!.existsSync(), isFalse);
  });

  test('同名文件重复写入不会重复落盘', () async {
    final txId = await newTransaction();
    await repo.add(transactionId: txId, bytes: _png, fileName: 'sha_x.png');
    await repo.add(transactionId: txId, bytes: _png, fileName: 'sha_x.png');
    expect(tmp.listSync().whereType<File>(), hasLength(1));
  });

  test('非法文件名被挡掉，不允许路径穿越', () async {
    final txId = await newTransaction();
    await expectLater(
      repo.add(
        transactionId: txId,
        bytes: _png,
        fileName: '../evil.png',
      ),
      throwsA(isA<ArgumentError>()),
    );
    expect(tmp.listSync().whereType<File>(), isEmpty);
  });

  test('清理孤儿文件时不动还有引用的图', () async {
    final txId = await newTransaction();
    await repo.add(transactionId: txId, bytes: _png, fileName: 'sha_keep.png');
    File('${tmp.path}/sha_orphan.png').writeAsBytesSync(_png);

    final removed = await repo.sweepOrphans();

    expect(removed, 1);
    expect(repo.fileFor('sha_keep.png')!.existsSync(), isTrue);
    expect(File('${tmp.path}/sha_orphan.png').existsSync(), isFalse);
  });
}
