import 'package:drift/drift.dart';

import '../db/app_database.dart';
import '../db/enums.dart';
import '../dedupe.dart';
import 'attachment_repository.dart';

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

/// 编辑一笔交易时可改的字段（金额已是整数分）；id 与去重键由仓储维护。
class TransactionEdit {
  const TransactionEdit({
    required this.type,
    required this.amountCents,
    required this.categoryId,
    required this.happenedAt,
    this.accountId,
    this.note = '',
    this.tags = const <String>[],
  });

  final EntryType type;
  final int amountCents;
  final String categoryId;
  final DateTime happenedAt;
  final String? accountId;
  final String note;
  final List<String> tags;
}

/// 编辑后会与另一笔交易的去重键相撞：拒绝保存，原记录保持不变。
class DuplicateTransactionException implements Exception {
  const DuplicateTransactionException(this.conflictingTransactionId);

  /// 撞上的那一笔的 id，便于调用方提示。
  final String conflictingTransactionId;

  @override
  String toString() => '已存在相同时间、金额与备注的记录';
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
  TransactionRepository(this._db, {AttachmentRepository? attachments})
      : _attachments = attachments;

  final AppDatabase _db;

  /// 删除交易时用它回收图片；为空时只删数据库记录（文件留给孤儿清理）。
  final AttachmentRepository? _attachments;

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
  /// 给定 `year` + `month` 时只读该自然月（半开区间，避免毫秒精度漏账），
  /// 且**不施加条数上限**——整月必须完整；不给月份时保留上限，兼容「看全部」的调用。
  ///
  /// 一次查交易 + 一次查分类 + 一次查账户 + 一次查附件计数，
  /// 分组与求和都在内存里做——单月几百条的量级，比 N+1 次查询划算得多。
  Future<List<DayGroup>> dayGroups({
    int? year,
    int? month,
    int limit = 500,
  }) async {
    final txQuery = _db.select(_db.transactions)
      ..orderBy([
        (t) => OrderingTerm(expression: t.happenedAt, mode: OrderingMode.desc),
      ]);
    if (year != null && month != null) {
      final start = DateTime(year, month);
      // DateTime 会把 month=13 规整成次年 1 月，跨年不用特判
      final end = DateTime(year, month + 1);
      txQuery.where(
        (t) =>
            t.happenedAt.isBiggerOrEqualValue(start) &
            t.happenedAt.isSmallerThanValue(end),
      );
    } else {
      txQuery.limit(limit);
    }
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
  Stream<List<DayGroup>> watchDayGroups({
    int? year,
    int? month,
    int limit = 500,
  }) async* {
    yield await dayGroups(year: year, month: month, limit: limit);
    yield* _db.tableUpdates().asyncMap(
          (_) => dayGroups(year: year, month: month, limit: limit),
        );
  }

  /// 编辑一笔交易：更新字段并重建标签关联（同名标签复用，旧关联整体替换）。
  ///
  /// 金额/时间/备注变化时按新值重算去重键；若与**另一笔**撞键则抛
  /// [DuplicateTransactionException]，原记录一字不动。附件不在这里处理——
  /// 图片的增删是独立能力，编辑只改交易自身的字段。
  Future<void> update(String id, TransactionEdit input) async {
    if (input.amountCents <= 0) {
      throw ArgumentError.value(input.amountCents, 'amountCents', '金额必须大于 0');
    }
    final note = input.note.trim();

    await _db.transaction(() async {
      final current = await (_db.select(_db.transactions)
            ..where((t) => t.id.equals(id)))
          .getSingleOrNull();
      if (current == null) {
        throw ArgumentError.value(id, 'id', '交易不存在');
      }

      final dedupeKey = dedupeKeyFor(
        happenedAt: input.happenedAt,
        amountCents: input.amountCents,
        note: note,
      );
      final sameKey = await (_db.select(_db.transactions)
            ..where((t) => t.dedupeKey.equals(dedupeKey)))
          .getSingleOrNull();
      if (sameKey != null && sameKey.id != id) {
        throw DuplicateTransactionException(sameKey.id);
      }

      await (_db.update(_db.transactions)..where((t) => t.id.equals(id))).write(
        TransactionsCompanion(
          type: Value(input.type),
          amountCents: Value(input.amountCents),
          categoryId: Value(input.categoryId),
          accountId: Value(input.accountId),
          note: Value(note),
          happenedAt: Value(input.happenedAt),
          dedupeKey: Value(dedupeKey),
        ),
      );

      await (_db.delete(_db.transactionTags)
            ..where((t) => t.transactionId.equals(id)))
          .go();
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
  }

  /// 删除一笔交易：标签关联与附件记录随外键级联消失，
  /// 图片文件按引用计数回收（仍被别的交易引用则保留）。
  Future<void> delete(String id) async {
    await _db.transaction(() async {
      // 必须在删交易之前回收：级联删掉附件记录后就读不到文件名了
      await _attachments?.removeForTransaction(id);
      await (_db.delete(_db.transactions)..where((t) => t.id.equals(id))).go();
    });
  }

  /// 读单笔明细（详情页用）；不存在时返回 null。
  Future<TransactionRow?> byId(String id) async {
    final tx = await (_db.select(_db.transactions)
          ..where((t) => t.id.equals(id)))
        .getSingleOrNull();
    if (tx == null) return null;

    final category = await (_db.select(_db.categories)
          ..where((c) => c.id.equals(tx.categoryId)))
        .getSingleOrNull();
    if (category == null) return null;

    final accountId = tx.accountId;
    final account = accountId == null
        ? null
        : await (_db.select(_db.accounts)..where((a) => a.id.equals(accountId)))
            .getSingleOrNull();

    final attachments = await (_db.select(_db.attachments)
          ..where((a) => a.transactionId.equals(id))
          ..orderBy([(a) => OrderingTerm(expression: a.sortOrder)]))
        .get();

    return TransactionRow(
      transaction: tx,
      category: category,
      account: account,
      attachmentCount: attachments.length,
      thumbnailFileName: attachments.isEmpty ? null : attachments.first.fileName,
    );
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
