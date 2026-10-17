import 'package:flutter/foundation.dart';

/// 明细页浏览的自然月（年 + 月），切月/算上下月的唯一入口。
@immutable
class LedgerMonth implements Comparable<LedgerMonth> {
  const LedgerMonth(this.year, this.month);

  /// 取某个时刻所在的自然月。
  factory LedgerMonth.of(DateTime time) => LedgerMonth(time.year, time.month);

  /// 当前自然月。
  factory LedgerMonth.current() => LedgerMonth.of(DateTime.now());

  final int year;
  final int month;

  LedgerMonth get previous =>
      month == 1 ? LedgerMonth(year - 1, 12) : LedgerMonth(year, month - 1);

  LedgerMonth get next =>
      month == 12 ? LedgerMonth(year + 1, 1) : LedgerMonth(year, month + 1);

  bool get isCurrent => this == LedgerMonth.current();

  /// 标题用「10月」：月份本身就是明细页的标题（见 DESIGN.md）。
  String get title => '$month月';

  String get subtitle => '$year年';

  @override
  int compareTo(LedgerMonth other) =>
      (year * 12 + month).compareTo(other.year * 12 + other.month);

  @override
  bool operator ==(Object other) =>
      other is LedgerMonth && other.year == year && other.month == month;

  @override
  int get hashCode => Object.hash(year, month);

  @override
  String toString() => '$year-${month.toString().padLeft(2, '0')}';
}
