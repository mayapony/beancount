import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/tokens.dart';
import 'bean_fab.dart';

/// 底部导航：4 Tab + 中间凹槽，金豆"嵌"在凹槽里。
///
/// 这里把金豆**放进导航栏自己的 Stack**，而不是用 `Scaffold.floatingActionButton`：
/// Scaffold 的绘制顺序是 body → FAB → bottomNavigationBar，底栏会盖住金豆的投影，
/// 只剩凹槽里的一弯月牙。自己排一层后，金豆和它的暖色投影都完整地压在底栏之上。
///
/// 凹槽用一个"固定圆心"的 [`_BeanNotchedShape`]：圆心固定在底栏顶边正中，
/// 不再依赖 Scaffold 的 FAB 几何量，所以可以脱离 Scaffold FAB 单独使用。
class BeanBottomNav extends StatelessWidget {
  const BeanBottomNav({
    super.key,
    required this.index,
    required this.onTap,
    required this.onFabTap,
  });

  final int index;
  final ValueChanged<int> onTap;

  /// 中间的记账金豆
  final VoidCallback onFabTap;

  static const double _barContentHeight = 68;
  static const double _notchGap = 78; // 凹槽直径：金豆 62 + 两侧各 8

  @override
  Widget build(BuildContext context) {
    final palette = BeanPalette.of(context);
    final safeBottom = math.min(MediaQuery.viewPaddingOf(context).bottom, 34.0);
    final barHeight = _barContentHeight + safeBottom;
    const fabRadius = BeanFab.size / 2;

    return SizedBox(
      // 只占底栏本身的高度：金豆"探出"的那 31px 用 Clip.none 画到外面，
      // 否则 Scaffold 会把这一段也算进底部安全区，内容区与底栏之间会空出一条死带。
      height: barHeight,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          // 底栏（凹槽形状）
          Positioned.fill(
            child: PhysicalShape(
              clipper: const ShapeBorderClipper(
                shape: _BeanNotchedShape(),
              ),
              color: palette.surface,
              elevation: 0,
              child: Padding(
                padding: EdgeInsets.only(bottom: safeBottom),
                child: Row(
                  children: [
                    Expanded(
                      child: _item(
                        palette,
                        0,
                        Icons.receipt_long_rounded,
                        '明细',
                      ),
                    ),
                    Expanded(
                      child: _item(
                        palette,
                        1,
                        Icons.donut_small_rounded,
                        '洞察',
                      ),
                    ),
                    const SizedBox(width: _notchGap),
                    Expanded(
                      child: _item(
                        palette,
                        2,
                        Icons.account_balance_wallet_rounded,
                        '资产',
                      ),
                    ),
                    Expanded(
                      child: _item(
                        palette,
                        3,
                        Icons.settings_rounded,
                        '设置',
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),

          // 顶边发丝线：中间给凹槽让出 78 宽
          Positioned(
            left: 0,
            right: 0,
            bottom: barHeight - BeanSpace.hairline,
            child: Row(
              children: [
                Expanded(
                  child: Container(
                    height: BeanSpace.hairline,
                    color: palette.border,
                  ),
                ),
                const SizedBox(width: _notchGap),
                Expanded(
                  child: Container(
                    height: BeanSpace.hairline,
                    color: palette.border,
                  ),
                ),
              ],
            ),
          ),

          // 金豆：圆心落在底栏顶边，向上探出半个身位（Clip.none 画到容器外）
          Positioned(
            top: -fabRadius,
            left: 0,
            right: 0,
            child: Center(child: BeanFab(onPressed: onFabTap)),
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
          Icon(icon, size: 24, color: color),
          const SizedBox(height: 2),
          Text(
            label,
            style: TextStyle(
              fontSize: 10,
              letterSpacing: 0.1,
              color: color,
              fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
            ),
          ),
        ],
      ),
    );
  }
}

/// 固定圆心的凹槽形状：圆心 = 底栏顶边正中。
class _BeanNotchedShape extends ShapeBorder {
  const _BeanNotchedShape();

  static const double _notchRadius = BeanFab.size / 2; // 31
  static const double _margin = 8;

  @override
  EdgeInsetsGeometry get dimensions => EdgeInsets.zero;

  @override
  Path getInnerPath(Rect rect, {TextDirection? textDirection}) =>
      getOuterPath(rect, textDirection: textDirection);

  @override
  Path getOuterPath(Rect rect, {TextDirection? textDirection}) {
    // Scaffold 的做法：把 FAB 的矩形外扩 notchMargin 后交给 NotchedShape
    final guest = Rect.fromCircle(
      center: Offset(rect.center.dx, rect.top),
      radius: _notchRadius + _margin,
    );
    return const CircularNotchedRectangle().getOuterPath(rect, guest);
  }

  @override
  void paint(Canvas canvas, Rect rect, {TextDirection? textDirection}) {}

  @override
  ShapeBorder scale(double t) => this;
}
