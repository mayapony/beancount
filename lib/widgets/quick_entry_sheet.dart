import 'package:flutter/material.dart';

import '../theme/tokens.dart';
import 'common.dart';

/// 记一笔的金额输入面板 —— 金豆按下直接进入，**一次点击**即可开始输入。
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

  void _press(String key) {
    setState(() {
      if (key == '⌫') {
        if (_amount.length <= 1) {
          _amount = '0';
        } else {
          _amount = _amount.substring(0, _amount.length - 1);
        }
        return;
      }
      if (key == '.') {
        if (!_amount.contains('.')) _amount = '$_amount.';
        return;
      }
      // 数字
      if (_amount.contains('.') && _amount.split('.')[1].length >= 2) return;
      if (_amount == '0') {
        _amount = key;
      } else {
        _amount = '$_amount$key';
      }
    });
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

          // 分类快选（最近常用在左）
          SizedBox(
            height: 68,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: BeanColors.categories.length,
              separatorBuilder: (_, __) => const SizedBox(width: 10),
              itemBuilder: (context, i) {
                final selected = _categoryIndex == i;
                return GestureDetector(
                  onTap: () => setState(() => _categoryIndex = i),
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
                        color: selected
                            ? BeanColors.gold
                            : Colors.transparent,
                      ),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        CategoryAvatar(categoryIndex: i, size: 34),
                        const SizedBox(height: 4),
                        Text(
                          BeanColors.categoryNames[i],
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight:
                                selected ? FontWeight.w700 : FontWeight.w400,
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

          // 键盘 + 完成（给定高度，stretch 才有意义）
          SizedBox(
            height: 240,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: Column(
                    children: [
                      _keypadRow(['7', '8', '9']),
                      _keypadRow(['4', '5', '6']),
                      _keypadRow(['1', '2', '3']),
                      _keypadRow(['.', '0', '⌫']),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                SizedBox(
                  width: 84,
                  child: _DoneButton(
                    enabled: _value > 0,
                    onTap: _value <= 0
                        ? null
                        : () {
                            widget.onSubmit(_value, _isIncome, _categoryIndex);
                            Navigator.of(context).pop();
                          },
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

  Widget _keypadRow(List<String> keys) {
    return Row(
      children: [
        for (final k in keys)
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(3),
              child: _KeyButton(label: k, onTap: () => _press(k)),
            ),
          ),
      ],
    );
  }
}

class _KeyButton extends StatelessWidget {
  const _KeyButton({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = BeanPalette.of(context);
    final isBackspace = label == '⌫';
    return Material(
      color: palette.surface,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: SizedBox(
          height: 54,
          child: Center(
            child: isBackspace
                ? Icon(
                    Icons.backspace_outlined,
                    size: 20,
                    color: palette.textSecondary,
                  )
                : Text(
                    label,
                    style: const TextStyle(
                      fontSize: 21,
                      fontWeight: FontWeight.w600,
                      fontFeatures: [FontFeature.tabularFigures()],
                    ),
                  ),
          ),
        ),
      ),
    );
  }
}

class _DoneButton extends StatelessWidget {
  const _DoneButton({required this.enabled, this.onTap});

  final bool enabled;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: enabled ? BeanColors.goldDeep : BeanColors.gold.withValues(alpha: 0.35),
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Center(
          child: Text(
            '完成',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: enabled ? Colors.white : Colors.white.withValues(alpha: 0.8),
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
