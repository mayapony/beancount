import 'dart:io';
import 'dart:typed_data';

import 'package:bean_count/data/db/app_database.dart';
import 'package:bean_count/data/db/connection.dart';
import 'package:bean_count/data/db/enums.dart';
import 'package:bean_count/data/repositories/attachment_repository.dart';
import 'package:bean_count/data/repositories/category_repository.dart';
import 'package:bean_count/data/repositories/transaction_repository.dart';
import 'package:bean_count/services/attachments/image_picker_service.dart';
import 'package:bean_count/services/entry/entry_writer.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late AppDatabase db;
  late TransactionRepository transactions;
  late AttachmentRepository attachments;
  late CategoryRepository categories;
  late EntryWriter writer;
  late Directory tmp;

  setUp(() async {
    db = AppDatabase(openInMemoryConnection());
    tmp = await Directory.systemTemp.createTemp('bean_entry_writer');
    attachments = AttachmentRepository(db, directory: tmp);
    transactions = TransactionRepository(db, attachments: attachments);
    categories = CategoryRepository(db);
    writer = EntryWriter(
      transactions: transactions,
      attachments: attachments,
    );
    await db.select(db.categories).get();
  });

  tearDown(() async {
    await db.close();
    if (await tmp.exists()) await tmp.delete(recursive: true);
  });

  Future<String> foodId() async =>
      (await categories.findByName('餐饮', CategoryType.expense))!.id;

  PickedImage image(String name, {int size = 4}) => PickedImage(
        bytes: Uint8List.fromList(List<int>.filled(size, 7)),
        fileName: name,
      );

  test('没有图片时只写交易', () async {
    final result = await writer.submit(
      type: EntryType.expense,
      amountCents: 3850,
      categoryId: await foodId(),
      happenedAt: DateTime(2026, 10, 18, 12),
      note: '牛肉面',
    );

    expect(result.inserted, isTrue);
    expect(await attachments.attachmentsOf(result.transactionId), isEmpty);
    expect(tmp.listSync().whereType<File>(), isEmpty);
  });

  test('带两张图片：落盘并按顺序建引用', () async {
    final result = await writer.submit(
      type: EntryType.expense,
      amountCents: 3850,
      categoryId: await foodId(),
      happenedAt: DateTime(2026, 10, 18, 12),
      note: '带图',
      images: [image('a.png'), image('b.png', size: 6)],
    );

    expect(result.inserted, isTrue);
    final rows = await attachments.attachmentsOf(result.transactionId);
    expect(rows, hasLength(2));
    expect(rows.first.fileName, 'a.png');
    expect(rows.last.fileName, 'b.png');
    expect(tmp.listSync().whereType<File>(), hasLength(2));
  });

  test('命中去重时不写图片', () async {
    final params = (
      amountCents: 3850,
      at: DateTime(2026, 10, 18, 12),
      category: await foodId(),
    );

    await writer.submit(
      type: EntryType.expense,
      amountCents: params.amountCents,
      categoryId: params.category,
      happenedAt: params.at,
      note: '重复',
      images: [image('first.png')],
    );
    final before = tmp.listSync().whereType<File>().length;

    final second = await writer.submit(
      type: EntryType.expense,
      amountCents: params.amountCents,
      categoryId: params.category,
      happenedAt: params.at,
      note: '重复',
      images: [image('second.png')],
    );

    expect(second.inserted, isFalse);
    expect(
      tmp.listSync().whereType<File>().length,
      before,
      reason: '账没新增，图也不该多出来',
    );
    expect(await transactions.count(), 1);
  });

  test('非法文件名被拒绝，不留文件', () async {
    await expectLater(
      writer.submit(
        type: EntryType.expense,
        amountCents: 100,
        categoryId: await foodId(),
        happenedAt: DateTime(2026, 10, 18, 12),
        images: [image('../evil.png')],
      ),
      throwsA(isA<ArgumentError>()),
    );
    expect(tmp.listSync().whereType<File>(), isEmpty);
  });

  test('选图文件名扩展名推断', () {
    expect(extensionOf('photo.PNG'), 'png');
    expect(extensionOf('noext'), 'jpg');
    expect(extensionOf('a.'), 'jpg');
    expect(extensionOf('a.verylongext'), 'jpg');
  });
}
