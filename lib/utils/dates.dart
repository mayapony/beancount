/// 记账时间文案：今天 18:34 / 昨天 21:05 / 10月15日 09:12（跨年补年份）。
///
/// 单独放一个文件是因为明细列表、记账面板、编辑页都要用同一套说法，
/// 各写一遍迟早会出现「今天」和「10月17日」混用。
String formatEntryTime(DateTime time, {DateTime? now}) {
  final reference = now ?? DateTime.now();
  final day = DateTime(time.year, time.month, time.day);
  final today = DateTime(reference.year, reference.month, reference.day);
  final diffDays = today.difference(day).inDays;
  final hm = '${time.hour.toString().padLeft(2, '0')}:'
      '${time.minute.toString().padLeft(2, '0')}';

  if (diffDays == 0) return '今天 $hm';
  if (diffDays == 1) return '昨天 $hm';
  if (diffDays == 2) return '前天 $hm';
  if (time.year == reference.year) return '${time.month}月${time.day}日 $hm';
  return '${time.year}年${time.month}月${time.day}日 $hm';
}

const _weekdays = <String>['周一', '周二', '周三', '周四', '周五', '周六', '周日'];

/// 明细页的日期分组头：今天 / 昨天 / 10月15日 周四。
String formatDayHeader(DateTime day, {DateTime? now}) {
  final reference = now ?? DateTime.now();
  final today = DateTime(reference.year, reference.month, reference.day);
  final date = DateTime(day.year, day.month, day.day);
  final diffDays = today.difference(date).inDays;
  final weekday = _weekdays[date.weekday - 1];

  if (diffDays == 0) return '今天 · $weekday';
  if (diffDays == 1) return '昨天 · $weekday';
  if (diffDays == 2) return '前天 · $weekday';
  if (date.year == reference.year) {
    return '${date.month}月${date.day}日 $weekday';
  }
  return '${date.year}年${date.month}月${date.day}日 $weekday';
}

/// 只到分钟的时间：12:30。
String formatClock(DateTime time) =>
    '${time.hour.toString().padLeft(2, '0')}:'
    '${time.minute.toString().padLeft(2, '0')}';

