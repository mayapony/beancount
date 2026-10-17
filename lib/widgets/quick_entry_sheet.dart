import 'package:flutter/material.dart';

import '../data/demo_data.dart';
import '../theme/tokens.dart';
import 'common.dart';

/// 记一笔的金额输入面板 —— 金豆按下直接进入，**一次点击**即可开始输入。
///
/// 键盘为「3 列数字 + 1 列功能」，完成按钮是功能列里的普通键，不再是一根竖条。
class QuickEntrySheet extends StatefulWidget {
  const QuickEntrySheet({
    super.key,
    required this.onSubmit,
  });

  final void Function(double amount, bool isIncome, int categoryIndex) onSubmit;

  @override
  State<QuickEntrySheet> createState() => _QuickEntrySheetState();
}

class _QuickEntrySheetState extends State<QuickEntrySheet> {
  bool _isIncome = false;
  int _categoryIndex = 0;
  String _amount = '0';

  double get _value => double.tryParse(_amount) ?? 0;

  void _appendDigit(String digit) {
    if (_amount.contains('.') && _amount.split('.')[1].length >= 2) return;
    _amount = _amount == '0' ? digit : '$_amount$digit';
  }

  void _press(String key) {
    setState(() {
      switch (key) {
        case '⌫':
          _amount = _amount.length <= 1
              ? '0'
              : _amount.substring(0, _amount.length - 1);
        case '.':
          if (!_amount.contains('.')) _amount = '$_amount.';
        case '00':
          _appendDigit('0');
          _appendDigit('0');
        default:
          _appendDigit(key);
      }
    });
  }

  void _notYet(String name) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('$name 将在 M3 实现')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final palette = BeanPalette.of(context);

    return SingleChildScrollView(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 支出 / 收入
            Row(
              children: [
                _TypePill(
                  label: '支出',
                  selected: !_isIncome,
                  onTap: () => setState(() => _isIncome = false),
                ),
                const SizedBox(width: 8),
                _TypePill(
                  label: '收入',
                  selected: _isIncome,
                  onTap: () => setState(() => _isIncome = true),
                ),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.close_rounded),
                  color: palette.textSecondary,
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),

            const SizedBox(height: 4),

            // 分类快选（高频在前）
            SizedBox(
              height: 68,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: kQuickCategoryOrder.length,
                separatorBuilder: (_, __) => const SizedBox(width: 10),
                itemBuilder: (context, i) {
                  final categoryIndex = kQuickCategoryOrder[i];
                  final selected = _categoryIndex == categoryIndex;
                  return GestureDetector(
                    onTap: () =>
                        setState(() => _categoryIndex = categoryIndex),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 150),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: selected
                            ? BeanColors.gold.withValues(alpha: 0.12)
                            : Colors.transparent,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color:
                              selected ? BeanColors.gold : Colors.transparent,
                        ),
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          CategoryAvatar(
                            categoryIndex: categoryIndex,
                            size: 34,
                          ),
                          const SizedBox(height: 4),
                          Text(
                            BeanColors.categoryNames[categoryIndex],
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: selected
                                  ? FontWeight.w700
                                  : FontWeight.w400,
                              color: selected
                                  ? BeanColors.goldDeep
                                  : palette.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),

            const SizedBox(height: 12),

            // 金额
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  '¥',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w600,
                    color: palette.textSecondary,
                  ),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    _amount,
                    textAlign: TextAlign.right,
                    style: TextStyle(
                      fontSize: 40,
                      fontWeight: FontWeight.w700,
                      fontFeatures: const [FontFeature.tabularFigures()],
                      color: _isIncome ? palette.income : palette.expense,
                    ),
                  ),
                ),
              ],
            ),

            Divider(height: 20, color: palette.border),

            // 键盘：3 列数字 + 1 列功能
            SizedBox(
              height: 240,
              child: Row(
                children: [
                  Expanded(
                    flex: 3,
                    child: Column(
                      children: [
                        _digitRow(['7', '8', '9']),
                        _digitRow(['4', '5', '6']),
                        _digitRow(['1', '2', '3']),
                        _digitRow(['.', '0', '00']),
                      ],
                    ),
                  ),
                  const SizedBox(width: 6),
                  SizedBox(
                    width: 60,
                    child: Column(
                      children: [
                        _funcKey(
                          icon: Icons.backspace_outlined,
                          onTap: () => _press('⌫'),
                        ),
                        _funcKey(
                          label: '日期',
                          onTap: () => _notYet('日期选择'),
                        ),
                        _funcKey(
                          label: '备注',
                          onTap: () => _notYet('备注输入'),
                        ),
                        _doneKey(),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _digitRow(List<String> keys) {
    return Expanded(
      child: Row(
        children: [
          for (final k in keys)
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(3),
                child: _KeyButton(label: k, onTap: () => _press(k)),
              ),
            ),
        ],
      ),
    );
  }

  Widget _funcKey({IconData? icon, String? label, required VoidCallback onTap}) {
    return Expanded(
      child: Padding(
        padding: const EdgeInsets.all(3),
        child: _KeyButton(icon: icon, label: label, onTap: onTap),
      ),
    );
  }

  Widget _doneKey() {
    final enabled = _value > 0;
    return Expanded(
      child: Padding(
        padding: const EdgeInsets.all(3),
        child: Material(
          color: enabled
              ? BeanColors.goldDeep
              : BeanColors.gold.withValues(alpha: 0.30),
          borderRadius: BorderRadius.circular(14),
          child: InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: enabled
                ? () {
                    widget.onSubmit(_value, _isIncome, _categoryIndex);
                    Navigator.of(context).pop();
                  }
                : null,
            child: Center(
              child: Text(
                '完成',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: enabled
                      ? Colors.white
                      : Colors.white.withValues(alpha: 0.85),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _KeyButton extends StatelessWidget {
  const _KeyButton({this.label, this.icon, required this.onTap});

  final String? label;
  final IconData? icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = BeanPalette.of(context);
    final isSymbol = icon != null || label == '.';
    return Material(
      color: palette.surface,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Center(
          child: icon != null
              ? Icon(icon, size: 19, color: palette.textSecondary)
              : Text(
                  label!,
                  style: TextStyle(
                    fontSize: isSymbol ? 17 : 21,
                    fontWeight: FontWeight.w600,
                    color: isSymbol && label != '.'
                        ? palette.textSecondary
                        : null,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
        ),
      ),
    );
  }
}

class _TypePill extends StatelessWidget {
  const _TypePill({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = BeanPalette.of(context);
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        decoration: BoxDecoration(
          color: selected
              ? BeanColors.gold.withValues(alpha: 0.16)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(BeanRadius.chip),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 14,
            fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
            color: selected ? BeanColors.goldDeep : palette.textSecondary,
          ),
        ),
      ),
    );
  }
}
