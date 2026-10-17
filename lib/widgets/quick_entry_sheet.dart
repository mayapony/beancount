import 'package:flutter/material.dart';

import '../data/demo_data.dart';
import '../theme/tokens.dart';
import '../utils/money.dart';
import 'common.dart';

/// 记一笔面板 —— 金豆按下直接进入，一次点击开始输入。
///
/// 结构参考成熟记账 App：
/// 支出/收入 → 分类（5 列、上下滑动、可见 3 行）→ 账户/日期 → 金额 + 图片入口
/// → 键盘（1-9 三行 + 右列 ⌫ / + / − / 完成 + 底部「再记」）。
/// 图片入口直接触发「上传即识别」（M0 为交互骨架，M7 接真实视觉模型）。
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

  /// 待计算的左操作数（支持 38.5 + 12 这类连续计算）
  double? _left;
  String? _op;

  /// 图片识别中
  bool _recognizing = false;

  double get _value => double.tryParse(_amount) ?? 0;

  double get _finalValue =>
      _op == null ? _value : _apply(_left ?? 0, _op!, _value);

  double _apply(double a, String op, double b) {
    if (op == '+') return a + b;
    if (op == '−') return a - b;
    return b;
  }

  void _appendDigit(String digit) {
    if (_amount.contains('.') && _amount.split('.')[1].length >= 2) return;
    _amount = _amount == '0' ? digit : '$_amount$digit';
  }

  void _press(String key) {
    setState(() {
      if (key == '⌫') {
        _amount =
            _amount.length <= 1 ? '0' : _amount.substring(0, _amount.length - 1);
      } else if (key == '.') {
        if (!_amount.contains('.')) _amount = '$_amount.';
      } else {
        _appendDigit(key);
      }
    });
  }

  void _pressOperator(String op) {
    setState(() {
      if (_op == null) {
        _left = _value;
        _op = op;
        _amount = '0';
      } else if (op == _op && _amount == '0') {
        // 重复点同一个运算符：取消待计算
        _op = null;
        _left = null;
      } else {
        _left = _apply(_left ?? 0, _op!, _value);
        _op = op;
        _amount = '0';
      }
    });
  }

  /// 图片入口：上传即识别（当前为交互骨架，M7 替换为真实视觉模型）
  Future<void> _recognizeBill() async {
    setState(() => _recognizing = true);
    await Future<void>.delayed(const Duration(milliseconds: 900));
    if (!mounted) return;
    setState(() {
      _recognizing = false;
      _amount = '38.50';
      _categoryIndex = 0;
      _isIncome = false;
      _left = null;
      _op = null;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('已识别：¥38.50 · 餐饮（M7 接入真实视觉模型）'),
      ),
    );
  }

  void _submit({bool keepOpen = false}) {
    widget.onSubmit(_finalValue, _isIncome, _categoryIndex);
    if (keepOpen) {
      setState(() {
        _amount = '0';
        _left = null;
        _op = null;
      });
    } else {
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = BeanPalette.of(context);

    return SingleChildScrollView(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── 支出 / 收入 ───────────────────────────────
            Row(
              children: [
                _TypePill(
                  label: '支出',
                  selected: !_isIncome,
                  onTap: () => setState(() => _isIncome = false),
                ),
                const SizedBox(width: 4),
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

            // ── 分类：5 列，上下滑动，可见 3 行 ─────────────
            SizedBox(
              height: 266,
              child: GridView.count(
                crossAxisCount: 5,
                padding: EdgeInsets.zero,
                mainAxisSpacing: 4,
                crossAxisSpacing: 2,
                childAspectRatio: 0.80,
                children: [
                  for (final index in kQuickCategoryOrder)
                    _CategoryCell(
                      categoryIndex: index,
                      selected: _categoryIndex == index,
                      onTap: () => setState(() => _categoryIndex = index),
                    ),
                ],
              ),
            ),

            const SizedBox(height: 8),

            // ── 账户 / 日期 ───────────────────────────────
            Row(
              children: [
                _MetaChip(
                  icon: Icons.account_balance_wallet_outlined,
                  label: '不选账户',
                  onTap: () => _notYet('账户选择'),
                ),
                const SizedBox(width: 8),
                _MetaChip(
                  icon: Icons.calendar_today_rounded,
                  label: '10月17日',
                  onTap: () => _notYet('日期选择'),
                ),
              ],
            ),

            const SizedBox(height: 10),

            // ── 金额 + 图片识别入口 ───────────────────────
            Container(
              padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
              decoration: BoxDecoration(
                color: palette.surface,
                borderRadius: BorderRadius.circular(BeanRadius.card),
                boxShadow: BeanShadow.soft,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (_op != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 2),
                      child: Text(
                        '${formatMoneyCompact(_left ?? 0)} $_op',
                        style: TextStyle(
                          fontSize: 12,
                          color: palette.textSecondary,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                    ),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Text(
                        '¥',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                          color: palette.textSecondary,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        _amount,
                        style: TextStyle(
                          fontSize: 32,
                          fontWeight: FontWeight.w700,
                          fontFeatures: const [FontFeature.tabularFigures()],
                          color: _isIncome ? palette.income : palette.expense,
                        ),
                      ),
                      const Spacer(),
                      if (_recognizing)
                        const Padding(
                          padding: EdgeInsets.only(right: 6),
                          child: SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: BeanColors.goldDeep,
                            ),
                          ),
                        ),
                      IconButton(
                        tooltip: '从相册识别',
                        icon: const Icon(Icons.image_outlined),
                        color: BeanColors.goldDeep,
                        onPressed: _recognizing ? null : _recognizeBill,
                      ),
                      IconButton(
                        tooltip: '拍照识别',
                        icon: const Icon(Icons.photo_camera_outlined),
                        color: BeanColors.goldDeep,
                        onPressed: _recognizing ? null : _recognizeBill,
                      ),
                    ],
                  ),
                ],
              ),
            ),

            const SizedBox(height: 10),

            // ── 键盘：4 列（1-9 / 右列功能 / 底部再记） ────
            SizedBox(
              height: 240,
              child: Column(
                children: [
                  _keyRow(const ['1', '2', '3'], right: _backspaceKey()),
                  _keyRow(
                    const ['4', '5', '6'],
                    right: _operatorKey('+'),
                  ),
                  _keyRow(
                    const ['7', '8', '9'],
                    right: _operatorKey('−'),
                  ),
                  _bottomKeyRow(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _notYet(String name) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('$name 将在 M3 实现')),
    );
  }

  Widget _keyRow(List<String> digits, {required Widget right}) {
    return Expanded(
      child: Row(
        children: [
          for (final d in digits)
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(3),
                child: _KeyButton(label: d, onTap: () => _press(d)),
              ),
            ),
          Expanded(child: Padding(padding: const EdgeInsets.all(3), child: right)),
        ],
      ),
    );
  }

  Widget _bottomKeyRow() {
    return Expanded(
      child: Row(
        children: [
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(3),
              child: _TextButton(
                label: '再记',
                color: BeanPalette.of(context).surface,
                textColor: BeanPalette.of(context).textSecondary,
                onTap: _finalValue > 0 ? () => _submit(keepOpen: true) : null,
              ),
            ),
          ),
          for (final d in const ['0', '.'])
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(3),
                child: _KeyButton(label: d, onTap: () => _press(d)),
              ),
            ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(3),
              child: _TextButton(
                label: '完成',
                color: _finalValue > 0
                    ? BeanColors.goldDeep
                    : BeanColors.gold.withValues(alpha: 0.30),
                textColor: Colors.white,
                onTap: _finalValue > 0 ? _submit : null,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _backspaceKey() {
    return _KeyButton(
      icon: Icons.backspace_outlined,
      onTap: () => _press('⌫'),
    );
  }

  Widget _operatorKey(String op) {
    final active = _op == op;
    return _TextButton(
      label: op,
      color: active
          ? BeanColors.gold.withValues(alpha: 0.22)
          : BeanPalette.of(context).surface,
      textColor: active ? BeanColors.goldDeep : BeanPalette.of(context).expense,
      fontSize: 22,
      onTap: () => _pressOperator(op),
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
              ? BeanColors.gold.withValues(alpha: 0.10)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected ? BeanColors.gold : Colors.transparent,
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CategoryAvatar(categoryIndex: categoryIndex, size: 38),
            const SizedBox(height: 3),
            Text(
              BeanColors.categoryNames[categoryIndex],
              style: TextStyle(
                fontSize: 10,
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

class _MetaChip extends StatelessWidget {
  const _MetaChip({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = BeanPalette.of(context);
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(BeanRadius.chip),
          border: Border.all(color: palette.border),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 13, color: palette.textSecondary),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(fontSize: 12, color: palette.textSecondary),
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
                    fontSize: label == '.' ? 17 : 22,
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

class _TextButton extends StatelessWidget {
  const _TextButton({
    required this.label,
    required this.color,
    required this.textColor,
    this.fontSize = 15,
    this.onTap,
  });

  final String label;
  final Color color;
  final Color textColor;
  final double fontSize;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: color,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Center(
          child: Text(
            label,
            style: TextStyle(
              fontSize: fontSize,
              fontWeight: FontWeight.w700,
              color: textColor,
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
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? BeanColors.goldDeep : Colors.transparent,
          borderRadius: BorderRadius.circular(BeanRadius.chip),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 14,
            fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
            color: selected ? Colors.white : palette.textSecondary,
          ),
        ),
      ),
    );
  }
}
