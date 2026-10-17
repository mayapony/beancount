import 'package:flutter/material.dart';

import '../data/demo_data.dart';
import '../theme/tokens.dart';
import '../utils/money.dart';
import 'common.dart';

/// 记一笔的金额输入面板 —— 金豆按下直接进入，**一次点击**即可开始输入。
///
/// 布局：分类网格（最多 3 行）+ 金额 + 键盘（3 列数字 + 1 列功能）。
/// 功能列：⌫ / 日期 / 运算符 / 完成；运算符键可循环 + − × ÷，支持连续计算。
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
  static const _ops = <String>['+', '−', '×', '÷'];

  bool _isIncome = false;
  int _categoryIndex = 0;
  String _amount = '0';

  /// 待计算的左操作数与运算符（支持「38.5 + 12」这类快速计算）
  double? _left;
  String? _op;

  double get _value => double.tryParse(_amount) ?? 0;

  double get _finalValue =>
      _op == null ? _value : _apply(_left ?? 0, _op!, _value);

  double _apply(double a, String op, double b) {
    switch (op) {
      case '+':
        return a + b;
      case '−':
        return a - b;
      case '×':
        return a * b;
      case '÷':
        return b == 0 ? a : a / b;
    }
    return b;
  }

  void _appendDigit(String digit) {
    if (_amount.contains('.') && _amount.split('.')[1].length >= 2) return;
    _amount = _amount == '0' ? digit : '$_amount$digit';
  }

  void _press(String key) {
    setState(() {
      switch (key) {
        case '⌫':
          _amount =
              _amount.length <= 1 ? '0' : _amount.substring(0, _amount.length - 1);
        case '.':
          if (!_amount.contains('.')) _amount = '$_amount.';
        default:
          _appendDigit(key);
      }
    });
  }

  void _pressOperator() {
    setState(() {
      if (_op == null) {
        _left = _value;
        _op = _ops.first;
        _amount = '0';
      } else if (_amount == '0') {
        // 尚未输入新数字：循环切换运算符
        final index = _ops.indexOf(_op!);
        _op = _ops[(index + 1) % _ops.length];
      } else {
        _left = _apply(_left ?? 0, _op!, _value);
        _amount = '0';
      }
    });
  }

  void _notYet(String name) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('$name 将在 M3 实现')),
    );
  }

  void _submit() {
    widget.onSubmit(_finalValue, _isIncome, _categoryIndex);
    Navigator.of(context).pop();
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

            // 分类网格：6 列，最多 3 行（一眼看到更多）
            GridView.count(
              crossAxisCount: 6,
              shrinkWrap: true,
              padding: EdgeInsets.zero,
              physics: const NeverScrollableScrollPhysics(),
              mainAxisSpacing: 2,
              crossAxisSpacing: 2,
              childAspectRatio: 0.84,
              children: [
                for (final index in kQuickCategoryOrder.take(18))
                  _CategoryCell(
                    categoryIndex: index,
                    selected: _categoryIndex == index,
                    onTap: () => setState(() => _categoryIndex = index),
                  ),
              ],
            ),

            const SizedBox(height: 10),

            // 金额（有未完成运算时，上方显示「左操作数 运算符」）
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
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      if (_op != null)
                        Text(
                          '${formatMoneyCompact(_left ?? 0)} $_op',
                          style: TextStyle(
                            fontSize: 13,
                            color: palette.textSecondary,
                            fontFeatures: const [
                              FontFeature.tabularFigures(),
                            ],
                          ),
                        ),
                      Text(
                        _amount,
                        textAlign: TextAlign.right,
                        style: TextStyle(
                          fontSize: 40,
                          fontWeight: FontWeight.w700,
                          fontFeatures: const [FontFeature.tabularFigures()],
                          color: _isIncome ? palette.income : palette.expense,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),

            Divider(height: 20, color: palette.border),

            // 键盘：3 列数字 + 1 列功能
            SizedBox(
              height: 236,
              child: Row(
                children: [
                  Expanded(
                    flex: 3,
                    child: Column(
                      children: [
                        _digitRow(['7', '8', '9']),
                        _digitRow(['4', '5', '6']),
                        _digitRow(['1', '2', '3']),
                        _lastDigitRow(),
                      ],
                    ),
                  ),
                  const SizedBox(width: 6),
                  SizedBox(
                    width: 58,
                    child: Column(
                      children: [
                        _functionKey(
                          icon: Icons.backspace_outlined,
                          onTap: () => _press('⌫'),
                        ),
                        _functionKey(
                          icon: Icons.calendar_today_rounded,
                          onTap: () => _notYet('日期选择'),
                        ),
                        _operatorKey(),
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

  /// 最后一行：`.` 一列 + `0` 两列（去掉 00 后更均衡）
  Widget _lastDigitRow() {
    return Expanded(
      child: Row(
        children: [
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(3),
              child: _KeyButton(label: '.', onTap: () => _press('.')),
            ),
          ),
          Expanded(
            flex: 2,
            child: Padding(
              padding: const EdgeInsets.all(3),
              child: _KeyButton(label: '0', onTap: () => _press('0')),
            ),
          ),
        ],
      ),
    );
  }

  Widget _functionKey({required IconData icon, required VoidCallback onTap}) {
    return Expanded(
      child: Padding(
        padding: const EdgeInsets.all(3),
        child: _KeyButton(icon: icon, onTap: onTap),
      ),
    );
  }

  Widget _operatorKey() {
    return Expanded(
      child: Padding(
        padding: const EdgeInsets.all(3),
        child: Material(
          color: BeanColors.gold.withValues(alpha: 0.14),
          borderRadius: BorderRadius.circular(14),
          child: InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: _pressOperator,
            child: Center(
              child: Text(
                _op ?? '+',
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                  color: BeanColors.goldDeep,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _doneKey() {
    final enabled = _finalValue > 0;
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
            onTap: enabled ? _submit : null,
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

class _CategoryCell extends StatelessWidget {
  const _CategoryCell({
    required this.categoryIndex,
    required this.selected,
    required this.onTap,
  });

  final int categoryIndex;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = BeanPalette.of(context);
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        decoration: BoxDecoration(
          color: selected
              ? BeanColors.gold.withValues(alpha: 0.12)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected ? BeanColors.gold : Colors.transparent,
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CategoryAvatar(categoryIndex: categoryIndex, size: 30),
            const SizedBox(height: 3),
            Text(
              BeanColors.categoryNames[categoryIndex],
              style: TextStyle(
                fontSize: 9.5,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w400,
                color: selected ? BeanColors.goldDeep : palette.textSecondary,
              ),
            ),
          ],
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
                    fontSize: label == '.' ? 17 : 21,
                    fontWeight: FontWeight.w600,
                    color: label == '.' ? palette.textSecondary : null,
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
