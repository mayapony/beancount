import '../../data/db/app_database.dart';
import '../../data/db/enums.dart';

/// 一个月里的实际执行日：`day` 超过当月天数时落到该月最后一天。
///
/// 31 号规则因此天然表达「月末」；29/30 在平年 2 月也一样落月末。
DateTime occurrenceDateIn(int year, int month, int day) {
  final lastDay = DateTime(year, month + 1, 0).day;
  return DateTime(year, month, day > lastDay ? lastDay : day);
}

/// 一期规则的标识：`yyyy-MM`。
String periodOf(DateTime date) =>
    '${date.year}-${date.month.toString().padLeft(2, '0')}';

/// 从规则起始月到 [now] 所在月之间，已经到日子的每一期（升序）。
///
/// 当月还没到执行日就不算「已到期」——不提前把未来的钱记掉。
List<DateTime> occurrencesUntil(RecurringRule rule, DateTime now) {
  final start = DateTime(rule.startYear, rule.startMonth);
  final end = DateTime(now.year, now.month);
  if (start.isAfter(end)) return const [];

  final result = <DateTime>[];
  var cursor = start;
  while (!cursor.isAfter(end)) {
    final at = occurrenceDateIn(cursor.year, cursor.month, rule.dayOfMonth);
    if (!at.isAfter(now)) result.add(at);
    cursor = DateTime(cursor.year, cursor.month + 1);
  }
  return result;
}

/// 列表里展示的「下次执行」：严格晚于今天的那一期。
DateTime nextDueDate(RecurringRule rule, DateTime now) {
  final today = DateTime(now.year, now.month, now.day);
  var cursor = DateTime(now.year, now.month);
  for (var i = 0; i < 60; i++) {
    final at = occurrenceDateIn(cursor.year, cursor.month, rule.dayOfMonth);
    if (at.isAfter(today)) return at;
    cursor = DateTime(cursor.year, cursor.month + 1);
  }
  return cursor;
}

/// 规则的人类可读周期描述。
String frequencyLabel(RecurringRule rule) {
  return rule.dayOfMonth >= 31 ? '每月月末' : '每月 ${rule.dayOfMonth} 日';
}

/// 规则类型到交易类型（转账规则的账户语义与普通交易一致）。
EntryType entryTypeOf(RecurringRule rule) => rule.type;
