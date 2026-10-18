import 'dart:io';
import 'dart:typed_data';

import 'package:bean_count/data/db/app_database.dart';
import 'package:bean_count/data/db/connection.dart';
import 'package:bean_count/data/db/enums.dart';
import 'package:bean_count/data/repositories/account_repository.dart';
import 'package:bean_count/data/repositories/attachment_repository.dart';
import 'package:bean_count/data/repositories/category_repository.dart';
import 'package:bean_count/data/repositories/transaction_repository.dart';
import 'package:bean_count/services/ocr/receipt_guess.dart';
import 'package:bean_count/services/screenshot/auto_entry.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late AppDatabase db;
  late CategoryRepository categories;
  late AccountRepository accounts;
  late TransactionRepository transactions;
  late AttachmentRepository attachments;
  late Directory tmp;
  late AutoScreenshotSaver saver;

  final now = DateTime(2026, 10, 18, 19, 27);

  setUp(() async {
    db = AppDatabase(openInMemoryConnection());
    categories = CategoryRepository(db);
    accounts = AccountRepository(db);
    tmp = await Directory.systemTemp.createTemp('bean_auto_entry');
    attachments = AttachmentRepository(db, directory: tmp);
    transactions = TransactionRepository(db, attachments: attachments);
    saver = AutoScreenshotSaver(db: db, attachments: attachments);
    await db.select(db.categories).get(); // 建库 + 种子
  });

  tearDown(() async {
    await db.close();
    if (await tmp.exists()) await tmp.delete(recursive: true);
  });

  ReceiptGuess guess({
    int? amount = 3002,
    String? category = '餐饮',
    String? account = '支付宝',
    String note = '满巍明生炸鸡架',
    List<String> tags = const ['微信支付'],
  }) {
    return ReceiptGuess(
      amountCents: amount,
      categoryName: category,
      accountName: account,
      note: note,
      tagNames: tags,
      happenedAt: now,
      confidence: amount == null
          ? ReceiptConfidence.categoryOnly
          : ReceiptConfidence.amount,
    );
  }

  test('识别出金额后直接记账，并保存原图', () async {
    final food = (await categories.findByName('餐饮', CategoryType.expense))!;
    final alipay = await accounts.ensure(name: '支付宝');

    final result = await saver.save(
      guess: guess(),
      imageBytes: Uint8List.fromList(<int>[1, 2, 3]),
      fileName: 'screenshot.jpg',
      autoTags: true,
      now: now,
    );

    expect(result.inserted, isTrue);
    expect(result.duplicate, isFalse);
    expect(result.categoryName, '餐饮');
    expect(result.accountName, '支付宝');

    final rows = await db.select(db.transactions).get();
    expect(rows, hasLength(1));
    final row = rows.single;
    expect(row.type, EntryType.expense);
    expect(row.amountCents, 3002);
    expect(row.categoryId, food.id);
    expect(row.accountId, alipay.id);
    expect(row.note, '满巍明生炸鸡架');
    expect(row.happenedAt, now);
    expect(await transactions.tagsOf(row.id), contains('微信支付'));

    final saved = await attachments.attachmentsOf(row.id);
    expect(saved, hasLength(1));
    final file = attachments.fileFor(saved.single.fileName);
    expect(file, isNotNull);
    expect(file!.existsSync(), isTrue);
  });

  test('同一笔重复识别命中 去重，不重复记账也不多留图片', () async {
    final first = await saver.save(
      guess: guess(),
      imageBytes: Uint8List.fromList(<int>[1, 2, 3]),
      fileName: 'screenshot.jpg',
      autoTags: false,
      now: now,
    );
    expect(first.inserted, isTrue);

    final second = await saver.save(
      guess: guess(),
      imageBytes: Uint8List.fromList(<int>[1, 2, 3]),
      fileName: 'screenshot.jpg',
      autoTags: false,
      now: now,
    );

    expect(second.inserted, isFalse);
    expect(second.duplicate, isTrue);
    expect(await db.select(db.transactions).get(), hasLength(1));
  });

  test('分类匹配不到时回落到「其他」', () async {
    final result = await saver.save(
      guess: guess(category: '一个不存在的分类', amount: 880),
      imageBytes: Uint8List.fromList(<int>[1]),
      fileName: 'screenshot.jpg',
      autoTags: false,
      now: now.add(const Duration(minutes: 1)),
    );

    expect(result.categoryName, '其他');
    final row = (await db.select(db.transactions).get()).single;
    final other = await categories.findByName('其他', CategoryType.expense);
    expect(row.categoryId, other!.id);
  });

  test('关闭自动标签时不写标签', () async {
    await saver.save(
      guess: guess(amount: 990),
      imageBytes: Uint8List.fromList(<int>[1]),
      fileName: 'screenshot.jpg',
      autoTags: false,
      now: now.add(const Duration(minutes: 2)),
    );

    final row = (await db.select(db.transactions).get()).single;
    expect(await transactions.tagsOf(row.id), isEmpty);
  });

  test('没有金额时拒绝自动记账', () async {
    expect(
      () => saver.save(
        guess: guess(amount: null),
        imageBytes: Uint8List.fromList(<int>[1]),
        fileName: 'screenshot.jpg',
        autoTags: true,
        now: now,
      ),
      throwsStateError,
    );
  });
}
