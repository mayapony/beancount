import 'package:flutter/material.dart';

import '../theme/tokens.dart';

/// 底部导航：4 Tab + 中间凹槽留给金豆 FAB。
///
/// 凹槽（CircularNotchedRectangle）让金豆"嵌"进底栏，视觉更和谐。
/// 注意：金豆的投影必须画在不被裁切的容器上，否则四角会残留方形暖色，
/// 让凹槽看起来像一块方色块（见 bean_fab.dart 注释）。
class BeanBottomNav extends StatelessWidget {
  const BeanBottomNav({
    super.key,
    required this.index,
    required this.onTap,
  });

  final int index;
  final ValueChanged<int> onTap;

  @override
  Widget build(BuildContext context) {
    final palette = BeanPalette.of(context);
    return BottomAppBar(
      shape: const CircularNotchedRectangle(),
      notchMargin: 8,
      height: 72,
      padding: EdgeInsets.zero,
      color: palette.surface,
      elevation: 0,
      child: Row(
        children: [
          Expanded(
            child: _item(palette, 0, Icons.receipt_long_rounded, '明细'),
          ),
          Expanded(
            child: _item(palette, 1, Icons.donut_small_rounded, '洞察'),
          ),
          const SizedBox(width: 78),
          Expanded(
            child: _item(
              palette,
              2,
              Icons.account_balance_wallet_rounded,
              '资产',
            ),
          ),
          Expanded(
            child: _item(palette, 3, Icons.settings_rounded, '设置'),
          ),
        ],
      ),
    );
  }

  Widget _item(BeanPalette palette, int i, IconData icon, String label) {
    final selected = index == i;
    final color = selected ? palette.goldDeep : palette.textSecondary;
    return InkResponse(
      onTap: () => onTap(i),
      radius: 28,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
            decoration: BoxDecoration(
              color: selected
                  ? palette.gold.withValues(alpha: 0.14)
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(BeanRadius.chip),
            ),
            child: Icon(icon, size: 22, color: color),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              color: color,
              fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
            ),
          ),
        ],
      ),
    );
  }
}
