import 'dart:convert';

import 'package:bean_count/data/db/app_database.dart';
import 'package:bean_count/data/db/connection.dart';
import 'package:bean_count/data/repositories/app_state_repository.dart';
import 'package:bean_count/services/ocr/receipt_guess.dart';
import 'package:bean_count/services/screenshot/pending_entry.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late AppDatabase db;
  late PendingScreenshotEntryStore store;

  setUp(() async {
    db = AppDatabase(openInMemoryConnection());
    store = PendingScreenshotEntryStore(AppStateRepository(db));
    await db.select(db.appState).get();
  });

  tearDown(() async => db.close());

  test('写入后能读回全部识别字段', () async {
    await store.write(
      PendingScreenshotEntry(
        id: 'shot-1',
        createdAt: DateTime.utc(2026, 10, 18, 12),
        imagePath: '/tmp/shot.jpg',
        guess: ReceiptGuess(
          amountCents: 4450,
          categoryName: '餐饮',
          tagNames: const ['咖啡', '微信支付'],
          accountName: '微信',
          note: '金豆餐厅',
          happenedAt: DateTime.utc(2026, 10, 18, 12, 30),
          confidence: ReceiptConfidence.amount,
        ),
      ),
    );

    final read = await store.peek();
    expect(read, isNotNull);
    expect(read!.id, 'shot-1');
    expect(read.imagePath, '/tmp/shot.jpg');
    expect(read.guess!.amountCents, 4450);
    expect(read.guess!.categoryName, '餐饮');
    expect(read.guess!.tagNames, ['咖啡', '微信支付']);
    expect(read.guess!.accountName, '微信');
    expect(read.guess!.note, '金豆餐厅');
    expect(read.guess!.happenedAt, DateTime.utc(2026, 10, 18, 12, 30));
    expect(read.guess!.confidence, ReceiptConfidence.amount);
    expect(read.error, isNull);
  });

  test('take 读一次就清掉，重复启动不会重复弹', () async {
    await store.write(
      PendingScreenshotEntry(
        id: 'shot-2',
        createdAt: DateTime.utc(2026, 10, 18, 12),
        guess: const ReceiptGuess(
          amountCents: 1200,
          confidence: ReceiptConfidence.amount,
        ),
      ),
    );

    final first = await store.take();
    final second = await store.take();

    expect(first, isNotNull);
    expect(second, isNull);
    expect(await store.peek(), isNull);
  });

  test('识别失败也保留一条，带上原因', () async {
    await store.write(
      PendingScreenshotEntry(
        id: 'shot-3',
        createdAt: DateTime.utc(2026, 10, 18, 12),
        imagePath: '/tmp/shot.jpg',
        error: '视觉识别失败',
      ),
    );

    final read = await store.peek();
    expect(read!.error, '视觉识别失败');
    expect(read.guess, isNull);
    expect(read.imagePath, '/tmp/shot.jpg');
  });

  test('多条按写入顺序排队，take 逐条取出', () async {
    for (var i = 1; i <= 3; i++) {
      await store.add(
        PendingScreenshotEntry(
          id: 'shot-$i',
          createdAt: DateTime.utc(2026, 10, 18, 12, i),
          guess: ReceiptGuess(
            amountCents: 1000 + i,
            confidence: ReceiptConfidence.amount,
          ),
        ),
      );
    }

    expect(await store.count(), 3);
    expect((await store.take())!.id, 'shot-1');
    expect((await store.peek())!.id, 'shot-2');
    expect((await store.take())!.id, 'shot-2');
    expect((await store.take())!.id, 'shot-3');
    expect(await store.take(), isNull);
    expect(await store.count(), 0);
  });

  test('超过上限时只保留最新的几条', () async {
    for (var i = 1; i <= PendingScreenshotEntryStore.kMaxEntries + 2; i++) {
      await store.add(
        PendingScreenshotEntry(
          id: 'shot-$i',
          createdAt: DateTime.utc(2026, 10, 18, 12, i),
        ),
      );
    }

    expect(await store.count(), PendingScreenshotEntryStore.kMaxEntries);
    expect((await store.peek())!.id, 'shot-3');
  });

  test('并发写入多条不会互相覆盖', () async {
    await Future.wait([
      for (var i = 0; i < 5; i++)
        store.add(
          PendingScreenshotEntry(
            id: 'parallel-$i',
            createdAt: DateTime.utc(2026, 10, 18, 12, i),
          ),
        ),
    ]);

    expect(await store.count(), 5);
  });

  test('两个消费者抢同一条时只有一个拿到', () async {
    await store.add(
      PendingScreenshotEntry(
        id: 'only-one',
        createdAt: DateTime.utc(2026, 10, 18, 12),
      ),
    );
    final other = PendingScreenshotEntryStore(AppStateRepository(db));

    final results = await Future.wait([store.take(), other.take()]);

    expect(results.whereType<PendingScreenshotEntry>().length, 1);
    expect(await store.count(), 0);
  });

  test('旧版单条 key 首次读取时迁移到队列', () async {
    final state = AppStateRepository(db);
    final legacy = PendingScreenshotEntry(
      id: 'legacy-shot',
      createdAt: DateTime.utc(2026, 10, 18, 12),
      guess: const ReceiptGuess(
        amountCents: 4450,
        confidence: ReceiptConfidence.amount,
      ),
    );
    await state.write(
      PendingScreenshotEntryStore.kLegacyKey,
      jsonEncode(legacy.toJson()),
    );

    final read = await store.peek();
    expect(read?.id, 'legacy-shot');
    expect(read?.guess?.amountCents, 4450);
    expect(await state.read(PendingScreenshotEntryStore.kLegacyKey), isNull);

    await store.take();
    expect(await store.count(), 0);
  });

  test('没有记录或数据损坏时返回 null，不抛异常', () async {
    expect(await store.peek(), isNull);

    final state = AppStateRepository(db);
    await state.write(
        '${PendingScreenshotEntryStore.kKeyPrefix}bad', 'not json');
    expect(await store.peek(), isNull);

    await state.write(PendingScreenshotEntryStore.kLegacyListKey, '{}');
    expect(await store.peek(), isNull);
  });
}
