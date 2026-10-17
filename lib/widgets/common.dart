import 'package:flutter/material.dart';

import '../theme/tokens.dart';

/// 圆角卡片：Soft UI 两层柔和阴影。
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
        boxShadow: BeanShadow.soft,
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
            style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
          ),
          const Spacer(),
          if (trailing != null) trailing!,
        ],
      ),
    );
  }
}

/// 分类圆底图标：彩色图标 + 同色系 8% 透明度圆底（tinted，轻盈不脏）。
class CategoryAvatar extends StatelessWidget {
  const CategoryAvatar({
    super.key,
    required this.categoryIndex,
    this.size = 40,
  });

  final int categoryIndex;
  final double size;

  static const _icons = <IconData>[
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

  @override
  Widget build(BuildContext context) {
    final color =
        BeanColors.categories[categoryIndex % BeanColors.categories.length];
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        shape: BoxShape.circle,
      ),
      child: Icon(
        _icons[categoryIndex % _icons.length],
        size: size * 0.5,
        color: color,
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

/// 顶部标题栏（页面通用）。
class BeanPageHeader extends StatelessWidget {
  const BeanPageHeader({
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
        12,
        BeanSpace.page,
        12,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                ),
              ),
              if (subtitle != null) ...[
                const SizedBox(height: 2),
                Text(
                  subtitle!,
                  style: TextStyle(fontSize: 12, color: palette.textSecondary),
                ),
              ],
            ],
          ),
          const Spacer(),
          ...actions,
        ],
      ),
    );
  }
}
