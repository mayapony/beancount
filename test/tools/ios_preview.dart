// 设计探索用的原型：只用于截图对比，不接入 App。
//
// 目的：验证两件事
// 1. 「果味」= 字体/材质/密度/发丝线/毛玻璃，而不是换成 CupertinoApp；
// 2. 去掉页面标题后，用「月份 + 本月收支」当锚点，页面不会失去重心。
import 'package:flutter/material.dart';

import 'package:bean_count/data/demo_data.dart';
import 'package:bean_count/theme/tokens.dart';
import 'package:bean_count/utils/money.dart';
import 'package:bean_count/widgets/common.dart';

// iOS 分组列表的暖色化改写：冷灰 #F2F2F7 → 暖灰
const _kGroupedBg = Color(0xFFF3EFE8);
const _kHairline = Color(0xFFE3DED6);

class IosHomePreview extends StatelessWidget {
  const IosHomePreview({super.key});

  @override
  Widget build(BuildContext context) {
    final palette = BeanPalette.of(context);
    final groups = demoDayGroups;
    final totalExpense = groups.fold<double>(0, (s, g) => s + g.expense);
    final totalIncome = groups.fold<double>(
      0,
      (s, g) =>
          s +
          g.items
              .where((t) => t.isIncome)
              .fold<double>(0, (a, t) => a + t.amount),
    );

    return ColoredBox(
      color: _kGroupedBg,
      child: SafeArea(
        bottom: false,
        child: Stack(
          children: [
            ListView(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 120),
              children: [
                // ── 没有"明细"标题：月份就是标题 ─────────────────
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          '10月',
                          style: TextStyle(
                            fontSize: 34,
                            height: 1.1,
                            fontWeight: FontWeight.w700,
                            letterSpacing: -0.6,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '2026年 · 4 笔收支',
                          style: TextStyle(
                            fontSize: 13,
                            color: palette.textSecondary,
                          ),
                        ),
                      ],
                    ),
                    const Spacer(),
                    _CircleButton(
                      icon: Icons.calendar_month_rounded,
                      onTap: () {},
                    ),
                  ],
                ),
                const SizedBox(height: 18),

                // ── 本月概览：无卡片、无阴影，只有一条发丝线 ──────
                Container(
                  decoration: BoxDecoration(
                    color: palette.surface,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  child: Row(
                    children: [
                      Expanded(
                          child: _Metric(
                              label: '支出',
                              value: '¥${formatMoney(totalExpense)}')),
                      _vLine(),
                      Expanded(
                          child: _Metric(
                              label: '收入',
                              value: '¥${formatMoney(totalIncome)}')),
                      _vLine(),
                      Expanded(
                        child: _Metric(
                          label: '结余',
                          value: '¥${formatMoney(totalIncome - totalExpense)}',
                          color: BeanColors.goldDeep,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 26),

                // ── 日期分组：小写灰字 + 右侧小计，iOS 分组列表观感 ──
                for (final group in groups) ...[
                  Padding(
                    padding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
                    child: Row(
                      children: [
                        Text(
                          '${group.date}  ${group.weekday}',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: palette.textSecondary,
                          ),
                        ),
                        const Spacer(),
                        Text(
                          '支出 ${formatMoney(group.expense)}',
                          style: TextStyle(
                            fontSize: 12,
                            color: palette.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    decoration: BoxDecoration(
                      color: palette.surface,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: Column(
                      children: [
                        for (var i = 0; i < group.items.length; i++) ...[
                          _Row(item: group.items[i]),
                          if (i != group.items.length - 1)
                            const Padding(
                              padding: EdgeInsets.only(left: 62),
                              child: Divider(
                                height: 0.5,
                                thickness: 0.5,
                                color: _kHairline,
                              ),
                            ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(height: 26),
                ],
              ],
            ),

            // ── 底栏：毛玻璃观感（用半透明 + 发丝线模拟，真机换 BackdropFilter） ──
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: Container(
                decoration: BoxDecoration(
                  color: palette.surface.withValues(alpha: 0.92),
                  border: const Border(
                    top: BorderSide(color: _kHairline, width: 0.5),
                  ),
                ),
                padding: const EdgeInsets.only(top: 8, bottom: 26),
                child: Row(
                  children: [
                    _tab(palette, Icons.receipt_long_rounded, '明细', true),
                    _tab(palette, Icons.donut_small_rounded, '洞察', false),
                    const SizedBox(width: 64), // 金豆让位
                    _tab(palette, Icons.account_balance_wallet_rounded, '资产',
                        false),
                    _tab(palette, Icons.settings_rounded, '设置', false),
                  ],
                ),
              ),
            ),

            // ── 品牌资产保留：金豆仍嵌在底栏中间，只是更小、更收敛 ──
            Positioned(
              left: 0,
              right: 0,
              bottom: 88,
              child: Center(
                child: Container(
                  width: 54,
                  height: 54,
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: BeanColors.goldGradient,
                    boxShadow: [
                      BoxShadow(
                        color: Color(0x33B45309),
                        blurRadius: 14,
                        offset: Offset(0, 4),
                      ),
                    ],
                  ),
                  child: const Icon(Icons.add_rounded,
                      color: Colors.white, size: 28),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _vLine() => Container(width: 0.5, height: 28, color: _kHairline);

  Widget _tab(BeanPalette palette, IconData icon, String label, bool selected) {
    final color = selected ? palette.goldDeep : palette.textSecondary;
    return Expanded(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 24, color: color),
          const SizedBox(height: 3),
          Text(
            label,
            style: TextStyle(
              fontSize: 10,
              fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

class _CircleButton extends StatelessWidget {
  const _CircleButton({required this.icon, required this.onTap});

  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = BeanPalette.of(context);
    return Material(
      color: palette.surface,
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: SizedBox(
          width: 36,
          height: 36,
          child: Icon(icon, size: 18, color: palette.textSecondary),
        ),
      ),
    );
  }
}

class _Metric extends StatelessWidget {
  const _Metric({required this.label, required this.value, this.color});

  final String label;
  final String value;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final palette = BeanPalette.of(context);
    return Column(
      children: [
        Text(label,
            style: TextStyle(fontSize: 12, color: palette.textSecondary)),
        const SizedBox(height: 4),
        Text(
          value,
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            letterSpacing: -0.2,
            color: color,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
      ],
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({required this.item});

  final DemoTransaction item;

  @override
  Widget build(BuildContext context) {
    final palette = BeanPalette.of(context);
    final color = BeanColors
        .categories[item.categoryIndex % BeanColors.categories.length];
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
      child: Row(
        children: [
          // iOS 设置页式的实心彩色圆 + 白色字形
          Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            child: Icon(
              kCategoryIcons[item.categoryIndex % kCategoryIcons.length],
              size: 16,
              color: Colors.white,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.title,
                  style: const TextStyle(
                    fontSize: 17,
                    letterSpacing: -0.2,
                    fontWeight: FontWeight.w400,
                  ),
                ),
                const SizedBox(height: 1),
                Text(
                  '${item.time} · ${BeanColors.categoryNames[item.categoryIndex]}',
                  style: TextStyle(fontSize: 13, color: palette.textSecondary),
                ),
              ],
            ),
          ),
          Text(
            '${item.isIncome ? '+' : '-'}${formatMoney(item.amount)}',
            style: TextStyle(
              fontSize: 17,
              letterSpacing: -0.2,
              fontWeight: FontWeight.w500,
              color: item.isIncome ? palette.income : palette.expense,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }
}
