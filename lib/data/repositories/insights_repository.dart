import 'package:drift/drift.dart';

import '../db/app_database.dart';
import '../db/enums.dart';

/// 时间范围：本月 / 本年 / 全部。
enum InsightsPeriod { month, year, all }

/// 一个分类在某段时间内的支出合计（已经上卷到一级分类）。
class CategoryTotal {
  const CategoryTotal({
    required this.category,
    required this.cents,
    required this.count,
  });

  final Category category;
  final int cents;
  final int count;
}

/// 趋势图上的一个点：日期（或月份）标签 + 支出合计。
class TrendPoint {
  const TrendPoint(this.label, this.cents);

  final String label;
  final int cents;
}

/// 洞察页需要的一整块数据。
class RangeInsights {
  const RangeInsights({
    required this.expenseCents,
    required this.incomeCents,
    required this.categories,
    required this.trend,
    required this.activeDays,
    required this.rangeLabel,
  });

  final int expenseCents;
  final int incomeCents;

  /// 按支出从大到小排好，金额为 0 的分类不出现。
  final List<CategoryTotal> categories;
  final List<TrendPoint> trend;

  /// 有支出的天数，用来算日均。
  final int activeDays;
  final String rangeLabel;

  int get netCents => incomeCents - expenseCents;

  double get dailyAverage =>
      activeDays == 0 ? 0 : expenseCents / activeDays / 100;
}

/// 统计仓储：分类聚合、趋势、日汇总。
///
/// 数据量是"单人账本"级别（几千条），所以整段读出来在内存里算，
/// 比在 SQL 里拼一堆 GROUP BY + 上卷父分类的 CTE 更好读也更好测。
class InsightsRepository {
  InsightsRepository(this._db);

  final AppDatabase _db;

  Stream<RangeInsights> watch({
    required InsightsPeriod period,
    DateTime? now,
  }) async* {
    yield await load(period: period, now: now);
    yield* _db.tableUpdates().asyncMap(
          (_) => load(period: period, now: now),
        );
  }

  Future<RangeInsights> load({
    required InsightsPeriod period,
    DateTime? now,
  }) async {
    final reference = now ?? DateTime.now();
    final (from, to, byMonth) = _rangeOf(period, reference);

    final query = _db.select(_db.transactions);
    if (from != null) {
      query.where((t) => t.happenedAt.isBiggerOrEqualValue(from));
    }
    if (to != null) {
      query.where((t) => t.happenedAt.isSmallerThanValue(to));
    }
    final rows = await query.get();

    final categories = {
      for (final c in await _db.select(_db.categories).get()) c.id: c,
    };

    var expense = 0;
    var income = 0;
    final byRoot = <String, int>{};
    final byRootCount = <String, int>{};
    final expenseDays = <DateTime>{};

    for (final tx in rows) {
      // 转账不是收支：它只改变账户余额，不进入任何统计
      if (tx.type == EntryType.transfer) continue;
      if (tx.type == EntryType.income) {
        income += tx.amountCents;
        continue;
      }
      expense += tx.amountCents;
      final leaf = categories[tx.categoryId];
      if (leaf == null) continue;
      // 二级分类上卷到父分类，保证「餐饮」不会因为记在「午餐」下而漏算
      final rootId = leaf.parentId ?? leaf.id;
      byRoot.update(rootId, (v) => v + tx.amountCents, ifAbsent: () => tx.amountCents);
      byRootCount.update(rootId, (v) => v + 1, ifAbsent: () => 1);
      expenseDays.add(DateTime(
        tx.happenedAt.year,
        tx.happenedAt.month,
        tx.happenedAt.day,
      ));
    }

    final totals = <CategoryTotal>[
      for (final entry in byRoot.entries)
        if (categories[entry.key] != null)
          CategoryTotal(
            category: categories[entry.key]!,
            cents: entry.value,
            count: byRootCount[entry.key] ?? 0,
          ),
    ]..sort((a, b) => b.cents.compareTo(a.cents));

    final trend = _buildTrend(
      rows: rows,
      from: from,
      to: to,
      byMonth: byMonth,
      reference: reference,
    );

    return RangeInsights(
      expenseCents: expense,
      incomeCents: income,
      categories: totals,
      trend: trend,
      activeDays: expenseDays.length,
      rangeLabel: _labelOf(period, reference),
    );
  }

  /// 返回 (from, to, 是否按月分桶)。
  (DateTime?, DateTime?, bool) _rangeOf(
    InsightsPeriod period,
    DateTime now,
  ) {
    switch (period) {
      case InsightsPeriod.month:
        final start = DateTime(now.year, now.month);
        return (start, DateTime(now.year, now.month + 1), false);
      case InsightsPeriod.year:
        return (DateTime(now.year), DateTime(now.year + 1), true);
      case InsightsPeriod.all:
        return (null, null, true);
    }
  }

  String _labelOf(InsightsPeriod period, DateTime now) {
    switch (period) {
      case InsightsPeriod.month:
        return '${now.year}年${now.month}月';
      case InsightsPeriod.year:
        return '${now.year}年';
      case InsightsPeriod.all:
        return '全部时间';
    }
  }

  List<TrendPoint> _buildTrend({
    required List<Transaction> rows,
    required DateTime? from,
    required DateTime? to,
    required bool byMonth,
    required DateTime reference,
  }) {
    DateTime? start = from;
    DateTime? end = to;
    if (start == null || end == null) {
      // 「全部」：从最早一笔所在月/日算到今天
      final earliest = rows.isEmpty
          ? reference
          : rows.map((r) => r.happenedAt).reduce((a, b) => a.isBefore(b) ? a : b);
      start ??= byMonth
          ? DateTime(earliest.year, earliest.month)
          : DateTime(earliest.year, earliest.month, earliest.day);
      end ??= byMonth
          ? DateTime(reference.year, reference.month + 1)
          : DateTime(reference.year, reference.month, reference.day + 1);
    }

    final buckets = <DateTime, int>{};
    final labels = <DateTime, String>{};

    if (byMonth) {
      var cursor = DateTime(start.year, start.month);
      while (cursor.isBefore(end)) {
        buckets[cursor] = 0;
        labels[cursor] = '${cursor.month}月';
        cursor = DateTime(cursor.year, cursor.month + 1);
      }
    } else {
      var cursor = DateTime(start.year, start.month, start.day);
      while (cursor.isBefore(end)) {
        buckets[cursor] = 0;
        labels[cursor] = '${cursor.day}';
        cursor = DateTime(cursor.year, cursor.month, cursor.day + 1);
      }
    }

    for (final tx in rows) {
      if (tx.type != EntryType.expense) continue;
      final key = byMonth
          ? DateTime(tx.happenedAt.year, tx.happenedAt.month)
          : DateTime(tx.happenedAt.year, tx.happenedAt.month, tx.happenedAt.day);
      if (!buckets.containsKey(key)) continue;
      buckets[key] = buckets[key]! + tx.amountCents;
    }

    final days = buckets.keys.toList()..sort();
    return [
      for (final day in days) TrendPoint(labels[day]!, buckets[day]!),
    ];
  }
}
