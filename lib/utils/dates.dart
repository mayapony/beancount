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
