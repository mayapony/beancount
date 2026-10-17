import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../data/demo_data.dart';
import '../theme/tokens.dart';
import '../utils/money.dart';
import '../widgets/common.dart';

class InsightsPage extends StatelessWidget {
  const InsightsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final palette = BeanPalette.of(context);
    final totalExpense =
        demoCategoryStats.fold<double>(0, (s, c) => s + c.value);
    final dailyAvg = totalExpense / 30;

    return SafeArea(
      bottom: false,
      child: ListView(
        padding: const EdgeInsets.only(bottom: 120),
        children: [
          const BeanPageHeader(
            title: '洞察',
            subtitle: '2026 年 10 月 · 支出',
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(BeanSpace.page, 8, BeanSpace.page, 16),
            child: const _CapsuleSwitcher(options: ['月', '年', '全部']),
          ),

          // ── 总支出 ────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: BeanSpace.page),
            child: BeanCard(
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '总支出',
                          style: TextStyle(
                            fontSize: 12,
                            color: palette.textSecondary,
                          ),
                        ),
                        const SizedBox(height: 6),
                        AmountText(
                          totalExpense,
                          showSign: false,
                          fontSize: 28,
                          fontWeight: FontWeight.w700,
                        ),
                      ],
                    ),
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        '日均',
                        style: TextStyle(
                          fontSize: 12,
                          color: palette.textSecondary,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        formatMoney(dailyAvg),
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: BeanSpace.section),

          // ── 分类占比（环形图） ─────────────────────────────
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: BeanSpace.page),
            child: BeanCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SectionTitle('分类占比'),
                  SizedBox(
                    height: 190,
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        PieChart(
                          PieChartData(
                            sectionsSpace: 3,
                            centerSpaceRadius: 58,
                            startDegreeOffset: -90,
                            sections: [
                              for (final stat in demoCategoryStats)
                                PieChartSectionData(
                                  value: stat.value,
                                  color: BeanColors
                                      .categories[stat.categoryIndex],
                                  radius: 22,
                                  showTitle: false,
                                ),
                            ],
                          ),
                        ),
                        Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              '本月支出',
                              style: TextStyle(
                                fontSize: 11,
                                color: palette.textSecondary,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              formatMoney(totalExpense),
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 14,
                    runSpacing: 8,
                    children: [
                      for (final stat in demoCategoryStats)
                        _LegendItem(
                          color: palette.chartColors[stat.categoryIndex],
                          name: stat.name,
                          value: stat.value,
                          total: totalExpense,
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: BeanSpace.section),

          // ── 收支趋势（折线 + 渐变面积） ────────────────────
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: BeanSpace.page),
            child: BeanCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SectionTitle(
                    '本月趋势',
                    trailing: Text(
                      '日均 ${formatMoneyCompact(dailyAvg)}',
                      style: TextStyle(
                        fontSize: 12,
                        color: palette.textSecondary,
                      ),
                    ),
                  ),
                  SizedBox(
                    height: 170,
                    child: LineChart(
                      LineChartData(
                        minX: 0,
                        maxX: (demoDailyTrend.length - 1).toDouble(),
                        minY: 0,
                        gridData: FlGridData(
                          show: true,
                          drawVerticalLine: false,
                          horizontalInterval: 50,
                          getDrawingHorizontalLine: (v) => FlLine(
                            color: palette.border,
                            strokeWidth: 1,
                          ),
                        ),
                        borderData: FlBorderData(show: false),
                        titlesData: FlTitlesData(
                          leftTitles: AxisTitles(
                            sideTitles: SideTitles(showTitles: false),
                          ),
                          rightTitles: AxisTitles(
                            sideTitles: SideTitles(showTitles: false),
                          ),
                          topTitles: AxisTitles(
                            sideTitles: SideTitles(showTitles: false),
                          ),
                          bottomTitles: AxisTitles(
                            sideTitles: SideTitles(
                              showTitles: true,
                              interval: 7,
                              reservedSize: 22,
                              getTitlesWidget: (value, meta) => Text(
                                '${value.toInt() + 1}',
                                style: TextStyle(
                                  fontSize: 10,
                                  color: palette.textSecondary,
                                ),
                              ),
                            ),
                          ),
                        ),
                        lineTouchData: LineTouchData(enabled: false),
                        lineBarsData: [
                          LineChartBarData(
                            spots: [
                              for (var i = 0; i < demoDailyTrend.length; i++)
                                FlSpot(i.toDouble(), demoDailyTrend[i]),
                            ],
                            isCurved: true,
                            curveSmoothness: 0.25,
                            color: BeanColors.gold,
                            barWidth: 3,
                            isStrokeCapRound: true,
                            dotData: FlDotData(show: false),
                            belowBarData: BarAreaData(
                              show: true,
                              gradient: LinearGradient(
                                begin: Alignment.topCenter,
                                end: Alignment.bottomCenter,
                                colors: [
                                  BeanColors.gold.withValues(alpha: 0.26),
                                  BeanColors.gold.withValues(alpha: 0.02),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: BeanSpace.section),

          // ── 分类排行 ─────────────────────────────────────
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: BeanSpace.page),
            child: BeanCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SectionTitle('分类排行'),
                  for (final stat in demoCategoryStats)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Row(
                        children: [
                          CategoryAvatar(
                            categoryIndex: stat.categoryIndex,
                            size: 32,
                          ),
                          const SizedBox(width: 10),
                          SizedBox(
                            width: 46,
                            child: Text(
                              stat.name,
                              style: const TextStyle(fontSize: 13),
                            ),
                          ),
                          Expanded(
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(999),
                              child: LinearProgressIndicator(
                                value: stat.value / totalExpense,
                                minHeight: 8,
                                backgroundColor:
                                    palette.chartColors[stat.categoryIndex]
                                        .withValues(alpha: 0.12),
                                valueColor: AlwaysStoppedAnimation<Color>(
                                  palette.chartColors[stat.categoryIndex],
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          SizedBox(
                            width: 72,
                            child: Text(
                              formatMoneyCompact(stat.value),
                              textAlign: TextAlign.right,
                              style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                fontFeatures: [FontFeature.tabularFigures()],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _LegendItem extends StatelessWidget {
  const _LegendItem({
    required this.color,
    required this.name,
    required this.value,
    required this.total,
  });

  final Color color;
  final String name;
  final double value;
  final double total;

  @override
  Widget build(BuildContext context) {
    final palette = BeanPalette.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 6),
        Text(name, style: const TextStyle(fontSize: 12)),
        const SizedBox(width: 4),
        Text(
          '${(value / total * 100).round()}%',
          style: TextStyle(fontSize: 12, color: palette.textSecondary),
        ),
      ],
    );
  }
}

class _CapsuleSwitcher extends StatefulWidget {
  const _CapsuleSwitcher({required this.options});

  final List<String> options;

  @override
  State<_CapsuleSwitcher> createState() => _CapsuleSwitcherState();
}

class _CapsuleSwitcherState extends State<_CapsuleSwitcher> {
  int _index = 0;

  @override
  Widget build(BuildContext context) {
    final palette = BeanPalette.of(context);
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: palette.gold.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(BeanRadius.chip),
      ),
      child: Row(
        children: [
          for (var i = 0; i < widget.options.length; i++)
            Expanded(
              child: GestureDetector(
                onTap: () => setState(() => _index = i),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  decoration: BoxDecoration(
                    color: _index == i ? palette.surface : Colors.transparent,
                    borderRadius: BorderRadius.circular(BeanRadius.chip),
                    boxShadow: _index == i ? BeanShadow.soft : null,
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    widget.options[i],
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight:
                          _index == i ? FontWeight.w700 : FontWeight.w500,
                      color: _index == i
                          ? BeanColors.goldDeep
                          : palette.textSecondary,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
