import 'package:drift/drift.dart';

import '../db/app_database.dart';
import '../db/enums.dart';

/// 走势的时间范围。
enum NetWorthRange {
  sixMonths('近6月'),
  thisYear('今年'),
  all('全部');

  const NetWorthRange(this.label);

  final String label;
}

/// 曲线上的一个点：某月月末的净资产。
class NetWorthPoint {
  const NetWorthPoint({
    required this.at,
    required this.label,
    required this.cents,
  });

  final DateTime at;
  final String label;
  final int cents;
}

/// 一段净资产走势。
class NetWorthSeries {
  const NetWorthSeries({required this.points, required this.hasData});

  final List<NetWorthPoint> points;

  /// 账本里是否有任何交易（没有就画不出"走势"，只能给空状态）。
  final bool hasData;

  bool get isEmpty => points.isEmpty || !hasData;

  int get current => points.isEmpty ? 0 : points.last.cents;

  int get startValue => points.isEmpty ? 0 : points.first.cents;

  /// 与区间起点相比的变化额。
  int get changeCents => current - startValue;
}

/// 净资产走势：**不存快照**，由「初始余额之和 + 截至该月的收入 − 支出」推导。
///
/// 转账在两个账户之间等额抵消，对全局净值没有影响，所以直接跳过。
/// 这样改账、删账、循环补记之后，曲线与账户余额永远一致。
class NetWorthRepository {
  NetWorthRepository(this._db);

  final AppDatabase _db;

  Stream<NetWorthSeries> watch({
    NetWorthRange range = NetWorthRange.sixMonths,
    DateTime? now,
  }) async* {
    yield await load(range: range, now: now);
    yield* _db.tableUpdates().asyncMap(
          (_) => load(range: range, now: now),
        );
  }

  Future<NetWorthSeries> load({
    NetWorthRange range = NetWorthRange.sixMonths,
    DateTime? now,
  }) async {
    final reference = now ?? DateTime.now();

    final initialRow = await _db
        .customSelect(
          'SELECT COALESCE(SUM(initial_balance_cents), 0) AS total FROM accounts',
        )
        .getSingle();
    final initialSum = initialRow.read<int>('total');

    final rows = await (_db.select(_db.transactions)
          ..orderBy([(t) => OrderingTerm(expression: t.happenedAt)]))
        .get();
    final hasData = rows.isNotEmpty;

    // 每月增量：收入为正、支出为负、转账跳过
    final deltas = <DateTime, int>{};
    DateTime? earliest;
    for (final row in rows) {
      final month = DateTime(row.happenedAt.year, row.happenedAt.month);
      earliest ??= month;
      if (earliest.isAfter(month)) earliest = month;
      final signed = switch (row.type) {
        EntryType.income => row.amountCents,
        EntryType.expense => -row.amountCents,
        EntryType.transfer => 0,
      };
      deltas.update(month, (v) => v + signed, ifAbsent: () => signed);
    }

    final currentMonth = DateTime(reference.year, reference.month);
    final (startMonth, endMonth) = _rangeOf(range, currentMonth, earliest);
    if (endMonth.isBefore(startMonth)) {
      return NetWorthSeries(points: const [], hasData: hasData);
    }

    // 起点之前的累计（含起点月之前的全部增量）
    var running = initialSum;
    for (final entry in deltas.entries) {
      if (entry.key.isBefore(startMonth)) running += entry.value;
    }

    final points = <NetWorthPoint>[];
    var cursor = startMonth;
    while (!cursor.isAfter(endMonth)) {
      running += deltas[cursor] ?? 0;
      points.add(
        NetWorthPoint(
          at: cursor,
          label: '${cursor.month}月',
          cents: running,
        ),
      );
      cursor = DateTime(cursor.year, cursor.month + 1);
    }

    return NetWorthSeries(points: points, hasData: hasData);
  }

  (DateTime start, DateTime end) _rangeOf(
    NetWorthRange range,
    DateTime currentMonth,
    DateTime? earliest,
  ) {
    switch (range) {
      case NetWorthRange.sixMonths:
        return (DateTime(currentMonth.year, currentMonth.month - 5), currentMonth);
      case NetWorthRange.thisYear:
        return (DateTime(currentMonth.year), currentMonth);
      case NetWorthRange.all:
        final start = earliest == null
            ? DateTime(currentMonth.year, currentMonth.month)
            : DateTime(earliest.year, earliest.month);
        if (start.isAfter(currentMonth)) {
          return (currentMonth, currentMonth);
        }
        return (start, currentMonth);
    }
  }
}
