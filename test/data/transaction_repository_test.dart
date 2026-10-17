import 'dart:io';

import 'package:bean_count/data/db/app_database.dart';
import 'package:bean_count/data/db/connection.dart';
import 'package:bean_count/data/db/enums.dart';
import 'package:bean_count/data/dedupe.dart';
import 'package:bean_count/data/repositories/account_repository.dart';
import 'package:bean_count/data/repositories/attachment_repository.dart';
import 'package:bean_count/data/repositories/category_repository.dart';
import 'package:bean_count/data/repositories/transaction_repository.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late AppDatabase db;
  late TransactionRepository repo;
  late CategoryRepository categories;

  setUp(() async {
    db = AppDatabase(openInMemoryConnection());
    repo = TransactionRepository(db);
    categories = CategoryRepository(db);
    await db.select(db.transactions).get(); // 触发建库 + 种子
  });

  tearDown(() async => db.close());

  Future<String> foodId() async =>
      (await categories.findByName('餐饮', CategoryType.expense))!.id;

  test('38.5 元以 3850 分落库', () async {
    final result = await repo.create(
      NewTransaction(
        type: EntryType.expense,
        amountCents: 3850,
        categoryId: await foodId(),
        happenedAt: DateTime(2026, 10, 17, 12, 30),
        note: '午餐',
      ),
    );

    expect(result.inserted, isTrue);
    final row = await (db.select(db.transactions)
          ..where((t) => t.id.equals(result.transactionId)))
        .getSingle();
    expect(row.amountCents, 3850);
    expect(row.note, '午餐');
  });

  test('同时间同金额同备注的第二次写入被拒绝', () async {
    final at = DateTime(2026, 10, 17, 12, 30);
    final first = await repo.create(
      NewTransaction(
        type: EntryType.expense,
        amountCents: 3850,
        categoryId: await foodId(),
        happenedAt: at,
        note: '聚餐  ',
      ),
    );
    final second = await repo.create(
      NewTransaction(
        type: EntryType.expense,
        amountCents: 3850,
        categoryId: await foodId(),
        happenedAt: at,
        note: '聚餐',
      ),
    );

    expect(first.inserted, isTrue);
    expect(second.inserted, isFalse);
    expect(second.transactionId, first.transactionId);
    expect(await repo.count(), 1);
  });

  test('不同备注、不同金额、不同时间都可写入', () async {
    final at = DateTime(2026, 10, 17, 12, 30);
    final category = await foodId();

    for (final (amount, note, time) in [
      (3850, '午餐', at),
      (3850, '晚餐', at),
      (3900, '午餐', at),
      (3850, '午餐', at.add(const Duration(minutes: 1))),
    ]) {
      final r = await repo.create(
        NewTransaction(
          type: EntryType.expense,
          amountCents: amount,
          categoryId: category,
          happenedAt: time,
          note: note,
        ),
      );
      expect(r.inserted, isTrue, reason: '$amount / $note / $time');
    }
    expect(await repo.count(), 4);
  });

  test('备注为空也能去重', () async {
    final at = DateTime(2026, 10, 17, 8);
    final category = await foodId();
    final a = await repo.create(
      NewTransaction(
        type: EntryType.expense,
        amountCents: 1200,
        categoryId: category,
        happenedAt: at,
      ),
    );
    final b = await repo.create(
      NewTransaction(
        type: EntryType.expense,
        amountCents: 1200,
        categoryId: category,
        happenedAt: at,
      ),
    );
    expect(a.inserted, isTrue);
    expect(b.inserted, isFalse);
  });

  test('标签自动创建且同名复用', () async {
    final category = await foodId();
    await repo.create(
      NewTransaction(
        type: EntryType.expense,
        amountCents: 1000,
        categoryId: category,
        happenedAt: DateTime(2026, 10, 17, 9),
        note: 'A',
        tags: ['报销', '出差'],
      ),
    );
    await repo.create(
      NewTransaction(
        type: EntryType.expense,
        amountCents: 2000,
        categoryId: category,
        happenedAt: DateTime(2026, 10, 17, 10),
        note: 'B',
        tags: ['报销'],
      ),
    );

    final tags = await db.select(db.tags).get();
    expect(tags.map((t) => t.name).toSet(), {'报销', '出差'});
    expect(await db.select(db.transactionTags).get(), hasLength(3));
  });

  test('按天分组倒序、支出小计正确', () async {
    final category = await foodId();
    await repo.create(
      NewTransaction(
        type: EntryType.expense,
        amountCents: 1000,
        categoryId: category,
        happenedAt: DateTime(2026, 10, 17, 9),
        note: '早',
      ),
    );
    await repo.create(
      NewTransaction(
        type: EntryType.expense,
        amountCents: 2000,
        categoryId: category,
        happenedAt: DateTime(2026, 10, 17, 12),
        note: '午',
      ),
    );
    await repo.create(
      NewTransaction(
        type: EntryType.income,
        amountCents: 500000,
        categoryId: (await categories.findByName('工资', CategoryType.income))!.id,
        happenedAt: DateTime(2026, 10, 16, 12),
        note: '工资',
      ),
    );

    final groups = await repo.dayGroups();
    expect(groups, hasLength(2));
    expect(groups.first.date, DateTime(2026, 10, 17));
    expect(groups.first.expenseCents, 3000);
    expect(groups.first.items.first.amountCents, 2000, reason: '组内按时间倒序');
    expect(groups.last.incomeCents, 500000);
  });

  test('按月查询：跨月边界正确，不吞不溢', () async {
    final category = await foodId();
    for (final (time, note) in [
      (DateTime(2026, 9, 30, 23, 59, 59), '九月末'),
      (DateTime(2026, 10, 1, 0, 0, 0), '十月一'),
      (DateTime(2026, 10, 31, 23, 59, 59), '十月末'),
      (DateTime(2026, 11, 1, 0, 0, 0), '十一月一'),
    ]) {
      await repo.create(
        NewTransaction(
          type: EntryType.expense,
          amountCents: 1000,
          categoryId: category,
          happenedAt: time,
          note: note,
        ),
      );
    }

    final october = await repo.dayGroups(year: 2026, month: 10);
    final notes = [
      for (final group in october)
        for (final row in group.items) row.transaction.note,
    ];
    expect(notes, unorderedEquals(['十月一', '十月末']));
  });

  test('按月查询：单月 600 笔不被截断', () async {
    final category = await foodId();
    for (var i = 0; i < 600; i++) {
      final result = await repo.create(
        NewTransaction(
          type: EntryType.expense,
          amountCents: 100 + i,
          categoryId: category,
          happenedAt: DateTime(2026, 10, 15, 12),
          note: '第$i笔',
        ),
      );
      expect(result.inserted, isTrue);
    }

    final october = await repo.dayGroups(year: 2026, month: 10);
    expect(october.fold<int>(0, (sum, g) => sum + g.items.length), 600);

    // 不指定月份时仍走 500 条上限（「看全部」类旧调用）
    final all = await repo.dayGroups();
    expect(all.fold<int>(0, (sum, g) => sum + g.items.length), 500);
  });

  test('delete 删除交易、标签关联与附件记录', () async {
    final dir = await Directory.systemTemp.createTemp('bean_del_');
    addTearDown(() => dir.delete(recursive: true));
    final attachments = AttachmentRepository(db, directory: dir);
    await attachments.ensureReady();
    final repoWithFiles = TransactionRepository(db, attachments: attachments);

    final created = await repoWithFiles.create(
      NewTransaction(
        type: EntryType.expense,
        amountCents: 3850,
        categoryId: await foodId(),
        happenedAt: DateTime(2026, 10, 17, 12, 30),
        note: '带图',
        tags: ['出差'],
      ),
    );
    await attachments.add(
      transactionId: created.transactionId,
      bytes: const [1, 2, 3],
      fileName: 'receipt.png',
    );

    await repoWithFiles.delete(created.transactionId);

    expect(await repoWithFiles.byId(created.transactionId), isNull);
    expect(
      await (db.select(db.transactionTags)
            ..where((t) => t.transactionId.equals(created.transactionId)))
          .get(),
      isEmpty,
    );
    expect(
      await (db.select(db.attachments)
            ..where((t) => t.transactionId.equals(created.transactionId)))
          .get(),
      isEmpty,
    );
  });

  test('update 撞到另一笔的去重键时被拒绝，两笔都不变', () async {
    final category = await foodId();
    final a = await repo.create(
      NewTransaction(
        type: EntryType.expense,
        amountCents: 3850,
        categoryId: category,
        happenedAt: DateTime(2026, 10, 17, 12, 30),
        note: '聚餐',
      ),
    );
    final b = await repo.create(
      NewTransaction(
        type: EntryType.expense,
        amountCents: 3850,
        categoryId: category,
        happenedAt: DateTime(2026, 10, 17, 12, 31),
        note: '聚餐',
      ),
    );

    await expectLater(
      repo.update(
        b.transactionId,
        TransactionEdit(
          type: EntryType.expense,
          amountCents: 3850,
          categoryId: category,
          happenedAt: DateTime(2026, 10, 17, 12, 30),
          note: '聚餐',
        ),
      ),
      throwsA(isA<DuplicateTransactionException>()),
    );

    final rowB = await repo.byId(b.transactionId);
    final rowA = await repo.byId(a.transactionId);
    expect(rowB!.transaction.happenedAt, DateTime(2026, 10, 17, 12, 31));
    expect(rowB.transaction.note, '聚餐');
    expect(rowA!.amountCents, 3850);
    expect(await repo.count(), 2);
  });

  test('update 改自已的去重键（只动金额/时间/备注）不会误判冲突', () async {
    final category = await foodId();
    final created = await repo.create(
      NewTransaction(
        type: EntryType.expense,
        amountCents: 3850,
        categoryId: category,
        happenedAt: DateTime(2026, 10, 17, 12, 30),
        note: '聚餐',
      ),
    );

    await repo.update(
      created.transactionId,
      TransactionEdit(
        type: EntryType.expense,
        amountCents: 4500,
        categoryId: category,
        happenedAt: DateTime(2026, 10, 17, 12, 30),
        note: '聚餐',
      ),
    );

    final row = await repo.byId(created.transactionId);
    expect(row!.amountCents, 4500);
    expect(row.transaction.dedupeKey,
        dedupeKeyFor(
          happenedAt: DateTime(2026, 10, 17, 12, 30),
          amountCents: 4500,
          note: '聚餐',
        ));
  });

  test('update 只改分类/账户/标签时去重键不变', () async {
    final account = (await AccountRepository(db).all()).first;
    final created = await repo.create(
      NewTransaction(
        type: EntryType.expense,
        amountCents: 3850,
        categoryId: await foodId(),
        happenedAt: DateTime(2026, 10, 17, 12, 30),
        note: '聚餐',
      ),
    );
    final before = (await repo.byId(created.transactionId))!.transaction;

    await repo.update(
      created.transactionId,
      TransactionEdit(
        type: EntryType.expense,
        amountCents: 3850,
        categoryId: before.categoryId,
        happenedAt: before.happenedAt,
        accountId: account.id,
        note: '聚餐',
        tags: ['家庭'],
      ),
    );

    final after = (await repo.byId(created.transactionId))!.transaction;
    expect(after.dedupeKey, before.dedupeKey);
    expect(after.accountId, account.id);
  });

  test('update 改写金额/类型/分类/账户/备注/标签', () async {
    final account = (await AccountRepository(db).all()).first;
    final created = await repo.create(
      NewTransaction(
        type: EntryType.expense,
        amountCents: 3850,
        categoryId: await foodId(),
        happenedAt: DateTime(2026, 10, 17, 12, 30),
        note: '午餐',
        tags: ['出差'],
      ),
    );

    await repo.update(
      created.transactionId,
      TransactionEdit(
        type: EntryType.income,
        amountCents: 4500,
        categoryId:
            (await categories.findByName('工资', CategoryType.income))!.id,
        happenedAt: DateTime(2026, 10, 18, 8, 15),
        accountId: account.id,
        note: '退款',
        tags: ['报销', '家庭'],
      ),
    );

    final row = await repo.byId(created.transactionId);
    expect(row, isNotNull);
    expect(row!.amountCents, 4500);
    expect(row.isIncome, isTrue);
    expect(row.category.name, '工资');
    expect(row.account?.id, account.id);
    expect(row.transaction.note, '退款');
    expect(row.transaction.happenedAt, DateTime(2026, 10, 18, 8, 15));

    final links = await (db.select(db.transactionTags)
          ..where((t) => t.transactionId.equals(created.transactionId)))
        .get();
    final tagNames = <String>[];
    for (final link in links) {
      final tag = await (db.select(db.tags)..where((t) => t.id.equals(link.tagId)))
          .getSingle();
      tagNames.add(tag.name);
    }
    expect(tagNames, unorderedEquals(['报销', '家庭']), reason: '旧标签关联整体替换');
  });

  test('byId 命中时带出分类与账户，不存在时返回 null', () async {
    final created = await repo.create(
      NewTransaction(
        type: EntryType.expense,
        amountCents: 3850,
        categoryId: await foodId(),
        happenedAt: DateTime(2026, 10, 17, 12, 30),
        note: '午餐',
      ),
    );

    final row = await repo.byId(created.transactionId);
    expect(row, isNotNull);
    expect(row!.amountCents, 3850);
    expect(row.category.name, '餐饮');
    expect(row.isIncome, isFalse);

    expect(await repo.byId('tx-不存在'), isNull);
  });

  test('按月订阅：只发该月数据，新增后自动重发', () async {
    final category = await foodId();
    await repo.create(
      NewTransaction(
        type: EntryType.expense,
        amountCents: 1100,
        categoryId: category,
        happenedAt: DateTime(2026, 9, 12, 9),
        note: '九月',
      ),
    );
    await repo.create(
      NewTransaction(
        type: EntryType.expense,
        amountCents: 2200,
        categoryId: category,
        happenedAt: DateTime(2026, 10, 12, 9),
        note: '十月',
      ),
    );

    final emissions =
        repo.watchDayGroups(year: 2026, month: 10).take(2).toList();
    await Future<void>.delayed(Duration.zero);
    await repo.create(
      NewTransaction(
        type: EntryType.expense,
        amountCents: 3300,
        categoryId: category,
        happenedAt: DateTime(2026, 10, 20, 9),
        note: '十月再来一笔',
      ),
    );

    final snapshots = await emissions;
    int countOf(List<DayGroup> groups) =>
        groups.fold<int>(0, (sum, g) => sum + g.items.length);

    expect(countOf(snapshots.first), 1, reason: '初次快照只有十月的 1 笔');
    expect(countOf(snapshots.last), 2, reason: '新增后就地重发，仍是 2 笔十月');
    expect(
      snapshots.last
          .expand((g) => g.items)
          .every((r) => r.transaction.happenedAt.month == 10),
      isTrue,
    );
  });

  test('去重键跨次计算稳定，且时间精确到秒', () {
    final a = dedupeKeyFor(
      happenedAt: DateTime(2026, 10, 17, 12, 30, 0),
      amountCents: 3850,
      note: '聚餐',
    );
    final b = dedupeKeyFor(
      happenedAt: DateTime(2026, 10, 17, 12, 30, 0, 999),
      amountCents: 3850,
      note: ' 聚餐 ',
    );
    expect(a, b);
    expect(a, hasLength(16));

    final c = dedupeKeyFor(
      happenedAt: DateTime(2026, 10, 17, 12, 30, 1),
      amountCents: 3850,
      note: '聚餐',
    );
    expect(c, isNot(a));
  });
}
