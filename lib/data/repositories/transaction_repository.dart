import 'package:drift/drift.dart';

import '../db/app_database.dart';
import '../../utils/fx.dart';
import '../db/enums.dart';
import '../dedupe.dart';
import 'attachment_repository.dart';
import 'ledger_filter.dart';

/// 新建一笔交易需要的全部信息（金额已是整数分）。
///
/// 转账：`type = transfer`，`accountId` 为转出、`toAccountId` 为转入，`categoryId` 为空。
class NewTransaction {
  const NewTransaction({
    required this.type,
    required this.amountCents,
    this.categoryId,
    required this.happenedAt,
    this.accountId,
    this.toAccountId,
    this.note = '',
    this.tags = const <String>[],
    this.source = EntrySource.manual,
    this.recurringRuleId,
    this.recurringPeriod,
    this.currency = 'CNY',
    this.originalAmountCents,
    this.ratePpm,
  });

  final EntryType type;
  final int amountCents;
  final String? categoryId;
  final DateTime happenedAt;
  final String? accountId;

  /// 仅转账使用：转入账户。
  final String? toAccountId;
  final String note;
  final List<String> tags;
  final EntrySource source;

  /// 由循环规则生成时：规则 id 与期数（`yyyy-MM`）。
  final String? recurringRuleId;
  final String? recurringPeriod;

  /// 原币档案：`currency != CNY` 时由界面传入原币金额与汇率。
  ///
  /// `amountCents` 永远是本位币金额（调用方或这里算好），统计只看它。
  final String currency;
  final int? originalAmountCents;
  final int? ratePpm;

  bool get isForeign => !isBaseCurrency(currency);

  bool get isTransfer => type == EntryType.transfer;
}

/// 编辑一笔交易时可改的字段（金额已是整数分）；id 与去重键由仓储维护。
class TransactionEdit {
  const TransactionEdit({
    required this.type,
    required this.amountCents,
    this.categoryId,
    required this.happenedAt,
    this.accountId,
    this.toAccountId,
    this.note = '',
    this.tags = const <String>[],
  });

  final EntryType type;
  final int amountCents;
  final String? categoryId;
  final DateTime happenedAt;
  final String? accountId;

  /// 仅转账使用：转入账户。
  final String? toAccountId;
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
    this.category,
    this.account,
    this.toAccount,
    this.attachmentCount = 0,
    this.thumbnailFileName,
  });

  final Transaction transaction;

  /// 转账没有分类，所以这里可空。
  final Category? category;
  final Account? account;

  /// 仅转账：转入账户。
  final Account? toAccount;
  final int attachmentCount;

  /// 第一张附件的文件名（没有图时为 null），列表用它画 32×32 缩略图。
  final String? thumbnailFileName;

  int get amountCents => transaction.amountCents;
  bool get isIncome => transaction.type == EntryType.income;
  bool get isExpense => transaction.type == EntryType.expense;
  bool get isTransfer => transaction.type == EntryType.transfer;

  /// 列表标题：备注优先；转账没有备注时用「A → B」。
  String get title {
    final note = transaction.note.trim();
    if (note.isNotEmpty) return note;
    if (isTransfer) {
      return '${account?.name ?? '账户'} → ${toAccount?.name ?? '账户'}';
    }
    return category?.name ?? '未分类';
  }
}

/// 明细页一次渲染所需的全部数据。
///
/// 除当月分组外还带上整库总笔数：只有它才能区分「一笔账都没有」和
/// 「这个月没有账，但别处有」——两种空状态给用户的说法完全不同。
/// 分类下钻的结果：按日分组 + 合计（只算支出）+ 笔数。
class CategoryLedger {
  const CategoryLedger({
    required this.groups,
    required this.totalCents,
    required this.count,
  });

  final List<DayGroup> groups;
  final int totalCents;
  final int count;

  bool get isEmpty => count == 0;
}

class LedgerSnapshot {
  const LedgerSnapshot({required this.groups, required this.totalCount});

  final List<DayGroup> groups;
  final int totalCount;

  bool get hasNothingAtAll => totalCount == 0;
}

/// 导出到 CSV 的一行：分类已经还原成「一级 / 二级」路径，附件是磁盘文件名。
class ExportRow {
  const ExportRow({
    required this.transaction,
    required this.categoryPath,
    this.accountName,
    this.toAccountName,
    this.tags = const <String>[],
    this.attachmentNames = const <String>[],
  });

  final Transaction transaction;

  /// 长度 1 表示只有一级分类；长度 2 是「一级, 二级」；转账为空。
  final List<String> categoryPath;
  final String? accountName;

  /// 仅转账：转入账户名。
  final String? toAccountName;
  final List<String> tags;
  final List<String> attachmentNames;
}

/// 搜索的结果：按日分组 + 命中数 + 是否被上限截断。
class SearchResult {
  const SearchResult({
    required this.groups,
    required this.matchedCount,
    this.truncated = false,
  });

  final List<DayGroup> groups;
  final int matchedCount;
  final bool truncated;

  bool get isEmpty => groups.isEmpty;
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
  /// - 转账必须给两端账户且互不相同、不需要分类；支出/收入必须有分类；
  /// - 计算去重键，命中已有记录时**不写入**并返回那笔的 id；
  /// - 标签自动创建（同名复用），与交易在同一事务里写入。
  Future<CreateResult> create(NewTransaction input) async {
    if (input.amountCents <= 0) {
      throw ArgumentError.value(input.amountCents, 'amountCents', '金额必须大于 0');
    }
    _validateShape(
      type: input.type,
      categoryId: input.categoryId,
      accountId: input.accountId,
      toAccountId: input.toAccountId,
    );

    final note = input.note.trim();
    // 外币：本位币金额由原币 × 汇率算出来，避免界面各处各算一遍
    var amountCents = input.amountCents;
    if (input.isForeign) {
      final rate = input.ratePpm;
      if (rate == null || rate <= 0) {
        throw ArgumentError('外币交易必须带汇率');
      }
      final original = input.originalAmountCents ?? input.amountCents;
      amountCents = baseCentsOf(originalCents: original, ratePpm: rate);
    }
    final dedupeKey = dedupeKeyFor(
      happenedAt: input.happenedAt,
      amountCents: amountCents,
      note: note,
      toAccountId: input.isTransfer ? input.toAccountId : null,
      salt: _saltOf(input.recurringRuleId, input.recurringPeriod),
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
              amountCents: amountCents,
              currency: Value(input.currency),
              originalAmountCents: Value(input.originalAmountCents),
              ratePpm: Value(input.ratePpm),
              categoryId: Value(input.categoryId),
              accountId: Value(input.accountId),
              toAccountId: Value(input.toAccountId),
              recurringRuleId: Value(input.recurringRuleId),
              recurringPeriod: Value(input.recurringPeriod),
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

  /// 循环补记的期数标记参与去重键：同规则同一期永远只生成一笔。
  static String? _saltOf(String? ruleId, String? period) {
    if (ruleId == null || period == null) return null;
    return 'rule:$ruleId:$period';
  }

  /// 收支/转账的字段约束：转账两端俱在且不同，收支必须有分类。
  void _validateShape({
    required EntryType type,
    required String? categoryId,
    required String? accountId,
    required String? toAccountId,
  }) {
    if (type == EntryType.transfer) {
      if (accountId == null || toAccountId == null) {
        throw ArgumentError('转账必须指定转出与转入账户');
      }
      if (accountId == toAccountId) {
        throw ArgumentError('转出与转入不能是同一个账户');
      }
      return;
    }
    if (categoryId == null) {
      throw ArgumentError('支出/收入必须有分类');
    }
  }

  /// 按天分组读取（倒序），用于明细页。
  ///
  /// 给定 `year` + `month` 时只读该自然月（半开区间，避免毫秒精度漏账），
  /// 且**不施加条数上限**——整月必须完整；不给月份时保留上限，兼容「看全部」的调用。
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
    return _groupByDay(await _rowsFor(rows));
  }

  /// 分类下钻：某个分类（含所有二级分类）在 [from, to) 内的账目，按日分组。
  ///
  /// 合计只算支出——下钻页回答的是"这一类花了多少"，转账与收入不进合计。
  Future<CategoryLedger> categoryLedger(
    String rootId, {
    DateTime? from,
    DateTime? to,
    int limit = 1000,
  }) async {
    final children = await childrenOfCategory(rootId);
    final ids = <String>[rootId, ...children.map((c) => c.id)];

    final query = _db.select(_db.transactions)
      ..where((t) => t.categoryId.isIn(ids))
      ..orderBy([
        (t) => OrderingTerm(expression: t.happenedAt, mode: OrderingMode.desc),
      ])
      ..limit(limit);

    if (from != null) {
      query.where((t) => t.happenedAt.isBiggerOrEqualValue(from));
    }
    if (to != null) {
      query.where((t) => t.happenedAt.isSmallerThanValue(to));
    }

    final rows = await query.get();
    if (rows.isEmpty) {
      return const CategoryLedger(groups: [], totalCents: 0, count: 0);
    }
    final groups = _groupByDay(await _rowsFor(rows));
    var total = 0;
    var count = 0;
    for (final group in groups) {
      total += group.expenseCents;
      count += group.items.length;
    }
    return CategoryLedger(groups: groups, totalCents: total, count: count);
  }

  /// 搜索：结构化条件交给 SQL，关键词在内存里匹配备注与关联名称。
  ///
  /// 先 SQL 收敛（类型 / 时间 / 分类含子级 / 账户 / 金额），再在剩余集合上做
  /// 关键词过滤——跨四张表做 `LIKE` 的代码量与索引成本都不划算，本地万级数据
  /// 在内存里匹配是毫秒级。
  Future<SearchResult> searchLedger(
    LedgerFilter filter, {
    int limit = 2000,
    DateTime? now,
  }) async {
    final bounds = filter.bounds(now ?? DateTime.now());
    final query = _db.select(_db.transactions)
      ..orderBy([
        (t) => OrderingTerm(expression: t.happenedAt, mode: OrderingMode.desc),
      ]);

    Expression<bool> condition = const Constant(true);
    final type = filter.type;
    if (type != null) {
      condition = condition & _db.transactions.type.equalsValue(type);
    }
    if (bounds.from != null) {
      condition = condition &
          _db.transactions.happenedAt
              .isBiggerOrEqualValue(bounds.from!);
    }
    if (bounds.to != null) {
      condition = condition &
          _db.transactions.happenedAt.isSmallerThanValue(bounds.to!);
    }
    final accountId = filter.accountId;
    if (accountId != null) {
      condition = condition & _db.transactions.accountId.equals(accountId);
    }
    if (filter.minCents != null) {
      condition = condition &
          _db.transactions.amountCents.isBiggerOrEqualValue(filter.minCents!);
    }
    if (filter.maxCents != null) {
      condition = condition &
          _db.transactions.amountCents.isSmallerOrEqualValue(filter.maxCents!);
    }

    final categoryId = filter.categoryId;
    if (categoryId != null) {
      final children = await childrenOfCategory(categoryId);
      condition = condition & _db.transactions.categoryId.isIn(
        [categoryId, ...children.map((c) => c.id)],
      );
    }

    // 关键词先在 SQL 里预筛一遍：否则 limit 会先把"最近 2000 笔"截出来，
    // 老账永远搜不到（1 万笔的护栏用例就是在这一步发现的）。
    // 这里只要求"是超集"，精确语义（一级分类名、标签）留给下面内存里那遍。
    final keywordRaw = filter.keyword.trim().toLowerCase();
    if (keywordRaw.isNotEmpty) {
      final like = '%${keywordRaw.replaceAll('%', '\\%').replaceAll('_', '\\_')}%';
      final allCategories = await _db.select(_db.categories).get();
      final byName = {
        for (final c in allCategories)
          if (c.name.toLowerCase().contains(keywordRaw)) c.id,
      };
      final parentIds = {for (final c in allCategories) if (c.parentId != null) c.parentId!};
      final matchingParents = byName.intersection(parentIds);
      final categoryIds = <String>{
        ...byName,
        for (final c in allCategories)
          if (c.parentId != null && matchingParents.contains(c.parentId)) c.id,
      };
      final matchingAccounts = {
        for (final a in await _db.select(_db.accounts).get())
          if (a.name.toLowerCase().contains(keywordRaw)) a.id,
      };
      final matchingTags = {
        for (final t in await _db.select(_db.tags).get())
          if (t.name.toLowerCase().contains(keywordRaw)) t.id,
      };
      final taggedIds = matchingTags.isEmpty
          ? const <String>{}
          : {
              for (final link in await (_db.select(_db.transactionTags)
                    ..where((t) => t.tagId.isIn(matchingTags.toList())))
                  .get())
                link.transactionId,
            };

      var keywordCondition =
          _db.transactions.note.lower().like(like) |
          _db.transactions.categoryId.isIn(categoryIds.toList());
      if (matchingAccounts.isNotEmpty) {
        keywordCondition = keywordCondition |
            _db.transactions.accountId.isIn(matchingAccounts.toList()) |
            _db.transactions.toAccountId.isIn(matchingAccounts.toList());
      }
      if (taggedIds.isNotEmpty) {
        keywordCondition =
            keywordCondition | _db.transactions.id.isIn(taggedIds.toList());
      }
      condition = condition & keywordCondition;
    }

    // 多取一条用于判断是否被截断
    query
      ..where((t) => condition)
      ..limit(limit + 1);
    final raw = await query.get();
    final truncated = raw.length > limit;
    final transactions = truncated ? raw.sublist(0, limit) : raw;

    final rows = await _rowsFor(transactions);
    final tagByTransaction = await tagsByTransaction();
    // 关键词要能顺着一级分类命中二级分类下的账（搜「餐饮」应包含「餐饮/外卖」）
    final categoryNames = {
      for (final c in await _db.select(_db.categories).get()) c.id: c.name,
    };

    final keyword = filter.keyword.trim().toLowerCase();
    var matched = keyword.isEmpty
        ? rows
        : rows.where((row) {
            final category = row.category;
            final parentName = category?.parentId == null
                ? ''
                : (categoryNames[category!.parentId] ?? '');
            final haystack = <String>[
              row.transaction.note,
              category?.name ?? '',
              parentName,
              row.account?.name ?? '',
              row.toAccount?.name ?? '',
              ...?tagByTransaction[row.transaction.id],
            ].join('\u0000').toLowerCase();
            return haystack.contains(keyword);
          }).toList();

    final tag = filter.tag;
    if (tag != null) {
      matched = matched
          .where((row) => (tagByTransaction[row.transaction.id] ?? const [])
              .contains(tag))
          .toList();
    }

    return SearchResult(
      groups: _groupByDay(matched),
      matchedCount: matched.length,
      truncated: truncated,
    );
  }

  /// 全部标签名（按名称排序）：搜索页的标签筛选用。
  Future<List<String>> allTagNames() async {
    final rows = await _db.select(_db.tags).get();
    return [for (final tag in rows) tag.name]..sort();
  }

  /// 某分类的子分类（搜索时「餐饮」要能带出「餐饮/外卖」）。
  Future<List<Category>> childrenOfCategory(String parentId) {
    return (_db.select(_db.categories)
          ..where((t) => t.parentId.equals(parentId)))
        .get();
  }

  /// 「交易 id → 标签名」的映射（搜索匹配与「按标签筛选」共用）。
  Future<Map<String, List<String>>> tagsByTransaction() async {
    final tagNames = {
      for (final tag in await _db.select(_db.tags).get()) tag.id: tag.name,
    };
    final result = <String, List<String>>{};
    for (final link in await _db.select(_db.transactionTags).get()) {
      final name = tagNames[link.tagId];
      if (name == null) continue;
      result.putIfAbsent(link.transactionId, () => []).add(name);
    }
    return result;
  }

  /// 把交易行装配成展示行（分类/账户/附件计数一次取齐）。
  Future<List<TransactionRow>> _rowsFor(List<Transaction> transactions) async {
    if (transactions.isEmpty) return const [];

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

    return [
      for (final tx in transactions)
        if (tx.type == EntryType.transfer ||
            categories[tx.categoryId] != null)
          TransactionRow(
            transaction: tx,
            category:
                tx.categoryId == null ? null : categories[tx.categoryId],
            account: tx.accountId == null ? null : accounts[tx.accountId],
            toAccount:
                tx.toAccountId == null ? null : accounts[tx.toAccountId],
            attachmentCount: attachmentCounts[tx.id] ?? 0,
            thumbnailFileName: thumbnails[tx.id],
          ),
    ];
  }

  /// 按天分组（倒序），并算好当天收支小计。
  ///
  /// 转账不是收支：它出现在分组里，但**不进** `expenseCents` / `incomeCents`。
  List<DayGroup> _groupByDay(List<TransactionRow> rows) {
    final byDay = <DateTime, List<TransactionRow>>{};
    for (final row in rows) {
      final at = row.transaction.happenedAt;
      final day = DateTime(at.year, at.month, at.day);
      byDay.putIfAbsent(day, () => []).add(row);
    }
    final days = byDay.keys.toList()..sort((a, b) => b.compareTo(a));
    return [
      for (final day in days)
        DayGroup(
          date: day,
          items: byDay[day]!,
          expenseCents: byDay[day]!
              .where((r) => r.isExpense)
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
    _validateShape(
      type: input.type,
      categoryId: input.categoryId,
      accountId: input.accountId,
      toAccountId: input.toAccountId,
    );
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
        toAccountId:
            input.type == EntryType.transfer ? input.toAccountId : null,
        // 自动补记的交易带着「规则 + 期数」：改了金额也不能丢掉这个标记，
        // 否则下次启动会把同一期再补一遍。
        salt: _saltOf(current.recurringRuleId, current.recurringPeriod),
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
          toAccountId: Value(input.toAccountId),
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

    final categoryId = tx.categoryId;
    final category = categoryId == null
        ? null
        : await (_db.select(_db.categories)..where((c) => c.id.equals(categoryId)))
            .getSingleOrNull();
    if (categoryId != null && category == null) return null;

    Future<Account?> accountOf(String? accountId) async => accountId == null
        ? null
        : await (_db.select(_db.accounts)
              ..where((a) => a.id.equals(accountId)))
            .getSingleOrNull();

    final account = await accountOf(tx.accountId);
    final toAccount = await accountOf(tx.toAccountId);

    final attachments = await (_db.select(_db.attachments)
          ..where((a) => a.transactionId.equals(id))
          ..orderBy([(a) => OrderingTerm(expression: a.sortOrder)]))
        .get();

    return TransactionRow(
      transaction: tx,
      category: category,
      account: account,
      toAccount: toAccount,
      attachmentCount: attachments.length,
      thumbnailFileName: attachments.isEmpty ? null : attachments.first.fileName,
    );
  }

  /// 「最近自动记账」：来源为 auto 的交易，按发生时间倒序，供事后审计列表用。
  Future<List<TransactionRow>> recentAutoEntries({int limit = 200}) async {
    final rows = await (_db.select(_db.transactions)
          ..where((t) => t.source.equalsValue(EntrySource.auto))
          ..orderBy([
            (t) => OrderingTerm(expression: t.happenedAt, mode: OrderingMode.desc),
          ])
          ..limit(limit))
        .get();
    if (rows.isEmpty) return const [];
    return _rowsFor(rows);
  }

  /// 明细页的完整快照：当月分组 + 整库总笔数。
  Future<LedgerSnapshot> ledger({
    int? year,
    int? month,
    int limit = 500,
  }) async {
    return LedgerSnapshot(
      groups: await dayGroups(year: year, month: month, limit: limit),
      totalCount: await count(),
    );
  }

  /// 明细页快照流：先发当前值，之后相关表有变化就重发。
  Stream<LedgerSnapshot> watchLedger({
    int? year,
    int? month,
    int limit = 500,
  }) async* {
    yield await ledger(year: year, month: month, limit: limit);
    yield* _db.tableUpdates().asyncMap(
          (_) => ledger(year: year, month: month, limit: limit),
        );
  }

  /// 最近用过的备注（去重、按最近使用倒序）：记一笔时作为快捷建议。
  Future<List<String>> recentNotes({int limit = 8}) async {
    final rows = await _db.customSelect(
      'SELECT note, MAX(happened_at) AS latest FROM transactions '
      "WHERE note <> '' GROUP BY note ORDER BY latest DESC LIMIT ?",
      variables: [Variable.withInt(limit)],
    ).get();
    return [for (final row in rows) row.read<String>('note')];
  }

  /// 某笔交易的标签名（详情页展示用，按标签名排序稳定）。
  Future<List<String>> tagsOf(String transactionId) async {
    final links = await (_db.select(_db.transactionTags)
          ..where((t) => t.transactionId.equals(transactionId)))
        .get();
    if (links.isEmpty) return const [];
    final ids = links.map((l) => l.tagId).toSet();
    final tags = await (_db.select(_db.tags)
          ..where((t) => t.id.isIn(ids)))
        .get();
    final names = tags.map((t) => t.name).toList()..sort();
    return names;
  }

  /// 导出用的全量数据：按发生时间升序，分类路径/账户名/标签/附件名一次装配好。
  ///
  /// 导出是「全量备份」语义，所以不分页、不分月——数据量级由用户自己的账本决定。
  Future<List<ExportRow>> exportRows() async {
    final transactions = await (_db.select(_db.transactions)
          ..orderBy([
            (t) => OrderingTerm(expression: t.happenedAt),
          ]))
        .get();
    if (transactions.isEmpty) return const [];

    final categories = {
      for (final c in await _db.select(_db.categories).get()) c.id: c,
    };
    final accounts = {
      for (final a in await _db.select(_db.accounts).get()) a.id: a,
    };
    final tagNames = {
      for (final t in await _db.select(_db.tags).get()) t.id: t.name,
    };

    final tagsByTransaction = <String, List<String>>{};
    for (final link in await _db.select(_db.transactionTags).get()) {
      final name = tagNames[link.tagId];
      if (name == null) continue;
      tagsByTransaction.putIfAbsent(link.transactionId, () => []).add(name);
    }

    final attachmentsByTransaction = <String, List<String>>{};
    final attachmentRows = await (_db.select(_db.attachments)
          ..orderBy([(a) => OrderingTerm(expression: a.sortOrder)]))
        .get();
    for (final attachment in attachmentRows) {
      attachmentsByTransaction
          .putIfAbsent(attachment.transactionId, () => [])
          .add(attachment.fileName);
    }

    return [
      for (final transaction in transactions)
        ExportRow(
          transaction: transaction,
          categoryPath: _categoryPath(transaction.categoryId, categories),
          accountName: transaction.accountId == null
              ? null
              : accounts[transaction.accountId!]?.name,
          toAccountName: transaction.toAccountId == null
              ? null
              : accounts[transaction.toAccountId!]?.name,
          tags: tagsByTransaction[transaction.id] ?? const [],
          attachmentNames:
              attachmentsByTransaction[transaction.id] ?? const [],
        ),
    ];
  }

  List<String> _categoryPath(
    String? categoryId,
    Map<String, Category> byId,
  ) {
    if (categoryId == null) return const [];
    final category = byId[categoryId];
    if (category == null) return const ['未分类'];
    final parentId = category.parentId;
    if (parentId == null) return [category.name];
    final parent = byId[parentId];
    return parent == null ? [category.name] : [parent.name, category.name];
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
