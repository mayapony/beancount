import 'package:flutter/material.dart';

import '../theme/tokens.dart';

/// 分组卡片：白底 + 0.5px 发丝线，**不用阴影**。
///
/// iOS 的 inset grouped list 靠"底色差 + 发丝线"分层，阴影是 Material 的语言。
class BeanCard extends StatelessWidget {
  const BeanCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(BeanSpace.card),
    this.onTap,
    this.radius = BeanRadius.card,
    this.color,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onTap;
  final double radius;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final palette = BeanPalette.of(context);
    final card = Container(
      padding: padding,
      decoration: BoxDecoration(
        color: color ?? palette.surface,
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(
          color: palette.border,
          width: BeanSpace.hairline,
        ),
      ),
      child: child,
    );
    if (onTap == null) return card;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(radius),
        child: card,
      ),
    );
  }
}

/// 页面大标题：34/w700 + 副行 13。**替代原来的「页面标题」**。
///
/// 用法上它承担三件事：定位（配 tab 高亮）、层级起点、视觉锚点。
/// 明细页放月份、资产页放净资产、洞察页放本月支出——标题本身是内容。
class BeanLargeTitle extends StatelessWidget {
  const BeanLargeTitle({
    super.key,
    required this.title,
    this.subtitle,
    this.actions = const [],
  });

  final String title;
  final String? subtitle;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    final palette = BeanPalette.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        BeanSpace.page,
        10,
        BeanSpace.page - 6,
        18,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 34,
                    height: 1.12,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.6,
                    color: Theme.of(context).colorScheme.onSurface,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
                if (subtitle != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    subtitle!,
                    style: TextStyle(
                      fontSize: 13,
                      color: palette.textSecondary,
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 8),
          ...actions,
        ],
      ),
    );
  }
}

/// 圆形图标按钮：白底 + 发丝线，替代 Material 的带底 chip。
class BeanCircleAction extends StatelessWidget {
  const BeanCircleAction({
    super.key,
    required this.icon,
    required this.onTap,
    this.tooltip,
  });

  final IconData icon;
  final VoidCallback onTap;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    final palette = BeanPalette.of(context);
    return Material(
      color: palette.surface,
      shape: CircleBorder(
        side: BorderSide(color: palette.border, width: BeanSpace.hairline),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: SizedBox(
          width: 38,
          height: 38,
          child: Icon(icon, size: 19, color: palette.textSecondary),
        ),
      ),
    );
  }
}

class SectionTitle extends StatelessWidget {
  const SectionTitle(this.text, {super.key, this.trailing});

  final String text;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          Text(
            text,
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              letterSpacing: -0.2,
            ),
          ),
          const Spacer(),
          if (trailing != null) trailing!,
        ],
      ),
    );
  }
}

/// 分类图标（与 `BeanColors.categoryNames` 同序）。
/// 记账面板的灰阶网格与列表行的彩色圆底共用这一份，避免两处各写一遍。
const kCategoryIcons = <IconData>[
  Icons.restaurant_rounded,
  Icons.directions_bus_rounded,
  Icons.shopping_bag_rounded,
  Icons.movie_rounded,
  Icons.home_rounded,
  Icons.local_hospital_rounded,
  Icons.school_rounded,
  Icons.flight_rounded,
  Icons.fitness_center_rounded,
  Icons.devices_rounded,
  Icons.pets_rounded,
  Icons.more_horiz_rounded,
];

/// 分类图标：**实心彩色圆 + 白色字形**（iOS 设置页 / 健康 App 的语言）。
///
/// 原来是"淡色圆底 + 彩线图标"，在分组列表里会显脏；实心圆在 28–30 尺寸下更清楚，
/// 也更符合果味方向。
class CategoryAvatar extends StatelessWidget {
  const CategoryAvatar({
    super.key,
    required this.categoryIndex,
    this.size = 30,
  });

  final int categoryIndex;
  final double size;

  @override
  Widget build(BuildContext context) {
    final color =
        BeanColors.categories[categoryIndex % BeanColors.categories.length];
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
      ),
      child: Icon(
        kCategoryIcons[categoryIndex % kCategoryIcons.length],
        size: size * 0.55,
        color: Colors.white,
      ),
    );
  }
}

/// 空状态 = 品牌叙事位：一颗种子 + 「种下第一笔」。
class BeanEmptyState extends StatelessWidget {
  const BeanEmptyState({
    super.key,
    this.title = '还没有记账',
    this.subtitle = '种下第一笔，让它发芽',
    this.icon = Icons.spa_rounded,
  });

  final String title;
  final String subtitle;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final palette = BeanPalette.of(context);
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 96,
            height: 96,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  BeanColors.gold.withValues(alpha: 0.22),
                  BeanColors.gold.withValues(alpha: 0.06),
                ],
              ),
            ),
            child: Icon(icon, size: 42, color: BeanColors.gold),
          ),
          const SizedBox(height: 20),
          Text(
            title,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 6),
          Text(
            subtitle,
            style: TextStyle(fontSize: 13, color: palette.textSecondary),
          ),
        ],
      ),
    );
  }
}
