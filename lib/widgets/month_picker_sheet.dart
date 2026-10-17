import 'package:flutter/material.dart';

import '../theme/tokens.dart';
import '../utils/month.dart';
import 'common.dart';

/// 选择浏览月份：年份步进 + 12 个月网格 + 「回到本月」。
///
/// 通过 [show] 以底部面板弹出，选中后返回 [LedgerMonth]；取消返回 null。
class MonthPickerSheet extends StatefulWidget {
  const MonthPickerSheet({super.key, required this.current});

  /// 当前浏览的月份（进来时高亮它）。
  final LedgerMonth current;

  static Future<LedgerMonth?> show(
    BuildContext context, {
    required LedgerMonth current,
  }) {
    return showModalBottomSheet<LedgerMonth>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => MonthPickerSheet(current: current),
    );
  }

  @override
  State<MonthPickerSheet> createState() => _MonthPickerSheetState();
}

class _MonthPickerSheetState extends State<MonthPickerSheet> {
  late int _year = widget.current.year;

  /// 年份下限/上限：超出范围时箭头置灰，避免一路翻到空年份。
  static const int _minYear = 2000;
  static const int _maxYear = 2100;

  void _stepYear(int delta) {
    final next = _year + delta;
    if (next < _minYear || next > _maxYear) return;
    setState(() => _year = next);
  }

  @override
  Widget build(BuildContext context) {
    final palette = BeanPalette.of(context);
    final thisMonth = LedgerMonth.current();

    return BeanSheet(
      title: '选择月份',
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              children: [
                IconButton(
                  tooltip: '上一年',
                  onPressed: _year > _minYear ? () => _stepYear(-1) : null,
                  icon: const Icon(Icons.chevron_left_rounded, size: 22),
                ),
                Text(
                  '$_year年',
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                IconButton(
                  tooltip: '下一年',
                  onPressed: _year < _maxYear ? () => _stepYear(1) : null,
                  icon: const Icon(Icons.chevron_right_rounded, size: 22),
                ),
                const Spacer(),
                TextButton(
                  onPressed: () =>
                      Navigator.of(context).pop(LedgerMonth.current()),
                  child: const Text('回到本月'),
                ),
              ],
            ),
          ),
          Center(
            child: ConstrainedBox(
              // 面板最宽 420：平板上也不会把 12 个月拉成长条
              constraints: const BoxConstraints(maxWidth: 420),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 4, 12, 4),
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  alignment: WrapAlignment.center,
                  children: [
                    for (var month = 1; month <= 12; month++)
                      SizedBox(
                        width: 76,
                        height: 44,
                        child: _MonthCell(
                          label: '$month月',
                          selected: month == widget.current.month &&
                              _year == widget.current.year,
                          isThisMonth: month == thisMonth.month &&
                              _year == thisMonth.year,
                          onTap: () => Navigator.of(context)
                              .pop(LedgerMonth(_year, month)),
                          palette: palette,
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MonthCell extends StatelessWidget {
  const _MonthCell({
    required this.label,
    required this.selected,
    required this.isThisMonth,
    required this.onTap,
    required this.palette,
  });

  final String label;
  final bool selected;

  /// 真实世界的「本月」：用描边额外标出来，和「正在浏览」区分开。
  final bool isThisMonth;
  final VoidCallback onTap;
  final BeanPalette palette;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? palette.goldDeep : palette.neutral.sand,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Container(
          alignment: Alignment.center,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: isThisMonth && !selected
                ? Border.all(color: palette.goldDeep, width: 1)
                : null,
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 15,
              fontWeight: selected || isThisMonth
                  ? FontWeight.w600
                  : FontWeight.w400,
              color: selected
                  ? Theme.of(context).colorScheme.onPrimary
                  : Theme.of(context).colorScheme.onSurface,
            ),
          ),
        ),
      ),
    );
  }
}
