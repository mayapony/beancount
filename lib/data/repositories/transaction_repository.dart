import 'package:drift/drift.dart';

import '../db/app_database.dart';
import '../db/enums.dart';
import '../dedupe.dart';

/// 新建一笔交易需要的全部信息（金额已是整数分）。
class NewTransaction {
  const NewTransaction({
    required this.type,
    required this.amountCents,
    required this.categoryId,
    required this.happenedAt,
    this.accountId,
    this.note = '',
    this.tags = const <String>[],
    this.source = EntrySource.manual,
  });

  final EntryType type;
  final int amountCents;
  final String categoryId;
  final DateTime happenedAt;
  final String? accountId;
  final String note;
  final List<String> tags;
  final EntrySource source;
}

/// 写入结果：`inserted=false` 表示命中去重键，库里已有这一笔。
class CreateResult {
  const CreateResult({required this.inserted, required this.transactionId});

  final bool inserted;

  /// 新增时是新记录的 id；已存在时是**已存在那笔**的 id。
  final String transactionId;
}

/// 某一天的明细：日期 + 当天交易（含分类/账户/附件数）。
class DayGroup {
  const DayGroup({
    required this.date,
    required this.items,
    required this.expenseCents,
    required this.incomeCents,
  });

  final DateTime date;
  final List<TransactionRow> items;
  final int expenseCents;
  final int incomeCents;

  int get netCents => incomeCents - expenseCents;
}

/// 明细行：交易 + 展示需要的关联信息。
class TransactionRow {
  const TransactionRow({
    required this.transaction,
    required this.category,
    this.account,
    this.attachmentCount = 0,
    this.thumbnailFileName,
  });

  final Transaction transaction;
  final Category category;
  final Account? account;
  final int attachmentCount;

  /// 第一张附件的文件名（没有图时为 null），列表用它画 32×32 缩略图。
  final String? thumbnailFileName;

  int get amountCents => transaction.amountCents;
  bool get isIncome => transaction.type == EntryType.income;
}

/// 交易仓储：写库、去重、按天读取。
class TransactionRepository {
  TransactionRepository(this._db);

  final AppDatabase _db;

  /// 新建交易。
  ///
  /// - 金额已经是整数分（调用方负责从用户输入精确换算）；
  /// - 计算去重键，命中已有记录时**不写入**并返回那笔的 id；
  /// - 标签自动创建（同名复用），与交易在同一事务里写入。
  Future<CreateResult> create(NewTransaction input) async {
    if (input.amountCents <= 0) {
      throw ArgumentError.value(input.amountCents, 'amountCents', '金额必须大于 0');
    }

    final note = input.note.trim();
    final dedupeKey = dedupeKeyFor(
      happenedAt: input.happenedAt,
      amountCents: input.amountCents,
      note: note,
    );

    final existing = await (_db.select(_db.transactions)
          ..where((t) => t.dedupeKey.equals(dedupeKey)))
        .getSingleOrNull();
    if (existing != null) {
      return CreateResult(inserted: false, transactionId: existing.id);
    }

    final id = _nextId();

    await _db.transaction(() async {
      await _db.into(_db.transactions).insert(
            TransactionsCompanion.insert(
              id: id,
              type: input.type,
              amountCents: input.amountCents,
              categoryId: input.categoryId,
              accountId: Value(input.accountId),
              note: Value(note),
              happenedAt: input.happenedAt,
              dedupeKey: dedupeKey,
              source: Value(input.source),
            ),
          );

      for (final tagName in input.tags) {
        final name = tagName.trim();
        if (name.isEmpty) continue;
        final tagId = await _ensureTag(name);
        await _db.into(_db.transactionTags).insert(
              TransactionTagsCompanion.insert(
                transactionId: id,
                tagId: tagId,
              ),
              mode: InsertMode.insertOrIgnore,
            );
      }
    });

    return CreateResult(inserted: true, transactionId: id);
  }

  /// 按天分组读取（倒序），用于明细页。
  ///
  /// 一次查交易 + 一次查分类 + 一次查账户 + 一次查附件计数，
  /// 分组与求和都在内存里做——单月几百条的量级，比 N+1 次查询划算得多。
  Future<List<DayGroup>> dayGroups({int limit = 500}) async {
    final txQuery = _db.select(_db.transactions)
      ..orderBy([
        (t) => OrderingTerm(expression: t.happenedAt, mode: OrderingMode.desc),
      ])
      ..limit(limit);
    final rows = await txQuery.get();
    if (rows.isEmpty) return const [];

    final categories = {
      for (final c in await _db.select(_db.categories).get()) c.id: c,
    };
    final accounts = {
      for (final a in await _db.select(_db.accounts).get()) a.id: a,
    };
    final attachmentCounts = <String, int>{};
    final thumbnails = <String, String>{};
    final attachmentRows = await (_db.select(_db.attachments)
          ..orderBy([(t) => OrderingTerm(expression: t.sortOrder)]))
        .get();
    for (final a in attachmentRows) {
      attachmentCounts.update(a.transactionId, (v) => v + 1, ifAbsent: () => 1);
      thumbnails.putIfAbsent(a.transactionId, () => a.fileName);
    }

    final byDay = <DateTime, List<TransactionRow>>{};
    for (final tx in rows) {
      final category = categories[tx.categoryId];
      if (category == null) continue; // 外键保证不会发生，防御性跳过
      final day = DateTime(tx.happenedAt.year, tx.happenedAt.month,
          tx.happenedAt.day);
      byDay.putIfAbsent(day, () => []).add(
            TransactionRow(
              transaction: tx,
              category: category,
              account: tx.accountId == null ? null : accounts[tx.accountId],
              attachmentCount: attachmentCounts[tx.id] ?? 0,
              thumbnailFileName: thumbnails[tx.id],
            ),
          );
    }

    final days = byDay.keys.toList()..sort((a, b) => b.compareTo(a));
    return [
      for (final day in days)
        DayGroup(
          date: day,
          items: byDay[day]!,
          expenseCents: byDay[day]!
              .where((r) => !r.isIncome)
              .fold(0, (sum, r) => sum + r.amountCents),
          incomeCents: byDay[day]!
              .where((r) => r.isIncome)
              .fold(0, (sum, r) => sum + r.amountCents),
        ),
    ];
  }

  /// 明细页的数据流：先发当前快照，之后任何相关表变化都重新查一遍。
  ///
  /// 用 `tableUpdates()` 而不是自己维护刷新回调：记账、导入、删附件
  /// 都会经过数据库，页面不需要知道"谁改了数据"。
  Stream<List<DayGroup>> watchDayGroups({int limit = 500}) async* {
    yield await dayGroups(limit: limit);
    yield* _db
        .tableUpdates()
        .asyncMap((_) => dayGroups(limit: limit));
  }

  /// 全部去重键：导入前用它判断哪些行已经存在。
  Future<Set<String>> dedupeKeys() async => {
        for (final row in await _db.select(_db.transactions).get())
          row.dedupeKey,
      };

  Future<int> count() async {
    final row = await _db
        .customSelect('SELECT COUNT(*) AS c FROM transactions')
        .getSingle();
    return row.read<int>('c');
  }

  /// 自增序号 + 微秒：批量导入时不会像纯随机那样撞 id。
  static int _seq = 0;

  String _nextId() =>
      'tx-${DateTime.now().microsecondsSinceEpoch}-${_seq++}';

  Future<String> _ensureTag(String name) async {
    final existing = await (_db.select(_db.tags)
          ..where((t) => t.name.equals(name)))
        .getSingleOrNull();
    if (existing != null) return existing.id;

    // id 由名称推导：同名标签必然得到同一个 id，两次并发创建也不会撞出
    // 「插入了但查不到」的竞态（用时间戳做 id 曾在快速连续写入时踩到过）。
    final id = 'tag-$name';
    await _db.into(_db.tags).insert(
          TagsCompanion.insert(id: id, name: name),
          mode: InsertMode.insertOrIgnore,
        );
    final created = await (_db.select(_db.tags)
          ..where((t) => t.name.equals(name)))
        .getSingleOrNull();
    if (created == null) {
      throw StateError('标签「$name」写入后读取不到');
    }
    return created.id;
  }
}
