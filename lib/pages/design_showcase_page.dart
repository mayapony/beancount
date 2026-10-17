import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../data/demo_data.dart';
import '../theme/app_theme.dart';
import '../theme/tokens.dart';
import '../utils/money.dart';
import '../widgets/common.dart';

/// 设计风格 Demo —— 把 docs/DESIGN.md 的 token 变成可触摸的页面，
/// 用来在实际设备上敲定设计。
class DesignShowcasePage extends StatefulWidget {
  const DesignShowcasePage({super.key});

  @override
  State<DesignShowcasePage> createState() => _DesignShowcasePageState();
}

class _DesignShowcasePageState extends State<DesignShowcasePage> {
  bool _darkPreview = false;

  @override
  Widget build(BuildContext context) {
    final palette = BeanPalette.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('设计规范'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: Switch.adaptive(
              value: _darkPreview,
              activeColor: BeanColors.goldDeep,
              onChanged: (v) => setState(() => _darkPreview = v),
            ),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(
          BeanSpace.page,
          8,
          BeanSpace.page,
          40,
        ),
        children: [
          // ── 品牌与色彩 ───────────────────────────────
          _Section(
            title: '品牌与色彩',
            subtitle: '金色是点缀色，占屏 ≤10%',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: const [
                    _Swatch(BeanColors.gold, '金 gold', '#F59E0B'),
                    _Swatch(BeanColors.goldDeep, '深金 gold-deep', '#B45309'),
                    _Swatch(BeanColors.beanGreenDeep, '豆绿', '#15803D'),
                    _Swatch(BeanColors.alertRedDeep, '警示红', '#BE123C'),
                    _Swatch(BeanColors.bgLight, '背景 · 亮', '#FAF7F2'),
                    _Swatch(BeanColors.textLight, '文字 · 亮', '#1C1917'),
                    _Swatch(BeanColors.bgDark, '背景 · 暗', '#161311'),
                    _Swatch(BeanColors.surfaceDark, '表面 · 暗', '#24201C'),
                  ],
                ),
                const SizedBox(height: 16),
                const _Label('渐变（仅用于金豆 FAB）'),
                const SizedBox(height: 8),
                Container(
                  height: 44,
                  decoration: BoxDecoration(
                    gradient: BeanColors.goldGradient,
                    borderRadius: BorderRadius.circular(BeanRadius.button),
                  ),
                ),
                const SizedBox(height: 16),
                const _Label('语义色（支出不刷红）'),
                const SizedBox(height: 8),
                _SemanticRow(
                  label: '收入',
                  child: AmountText(1280, isIncome: true, fontSize: 16),
                ),
                _SemanticRow(
                  label: '支出',
                  child: AmountText(38.5, fontSize: 16),
                ),
                _SemanticRow(
                  label: '转账',
                  child: AmountText(200, isTransfer: true, fontSize: 16),
                ),
                _SemanticRow(
                  label: '警示',
                  child: Text(
                    '超预算',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: palette.alert,
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                const _Label('分类色板（12 色）'),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    for (var i = 0; i < BeanColors.categories.length; i++)
                      Column(
                        children: [
                          CategoryAvatar(categoryIndex: i, size: 38),
                          const SizedBox(height: 4),
                          Text(
                            BeanColors.categoryNames[i],
                            style: const TextStyle(fontSize: 10),
                          ),
                        ],
                      ),
                  ],
                ),
              ],
            ),
          ),

          // ── 文字与数字 ───────────────────────────────
          _Section(
            title: '文字与数字',
            subtitle: '金额等宽 + 千分位',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: const [
                Text(
                  '34 / 余额 · 净资产',
                  style: TextStyle(fontSize: 34, fontWeight: FontWeight.w700),
                ),
                SizedBox(height: 6),
                Text(
                  '24 / 页面标题',
                  style: TextStyle(fontSize: 24, fontWeight: FontWeight.w700),
                ),
                SizedBox(height: 6),
                Text(
                  '17 / 区块标题',
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
                ),
                SizedBox(height: 6),
                Text('15 / 正文 Regular', style: TextStyle(fontSize: 15)),
                SizedBox(height: 6),
                Text('12 / 辅助信息', style: TextStyle(fontSize: 12)),
                SizedBox(height: 16),
                _Label('金额格式'),
                SizedBox(height: 8),
                _AmountSpecimen(),
              ],
            ),
          ),

          // ── 形状与阴影 ───────────────────────────────
          _Section(
            title: '形状与阴影',
            subtitle: 'Soft UI 两层柔和阴影',
            child: Wrap(
              spacing: 12,
              runSpacing: 12,
              children: const [
                _RadiusCard(8, '8'),
                _RadiusCard(14, '14'),
                _RadiusCard(18, '18'),
                _RadiusCard(24, '24'),
              ],
            ),
          ),

          // ── 组件 ─────────────────────────────────────
          _Section(
            title: '组件',
            subtitle: '按钮 / 列表项 / 空状态',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    FilledButton(
                      onPressed: () {},
                      child: const Text('主按钮'),
                    ),
                    OutlinedButton(
                      onPressed: () {},
                      child: const Text('次按钮'),
                    ),
                    TextButton(
                      onPressed: () {},
                      child: const Text('文字按钮'),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                const _Label('交易列表项'),
                const SizedBox(height: 8),
                BeanCard(
                  padding: const EdgeInsets.symmetric(
                    horizontal: BeanSpace.card,
                    vertical: 12,
                  ),
                  child: Row(
                    children: [
                      const CategoryAvatar(categoryIndex: 0),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              '楼下豆浆油条',
                              style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              '餐饮 · 08:12',
                              style: TextStyle(
                                fontSize: 12,
                                color: palette.textSecondary,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const AmountText(8.5, fontSize: 15),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                const _Label('空状态（品牌叙事位）'),
                const SizedBox(height: 8),
                BeanCard(
                  child: const SizedBox(
                    height: 200,
                    child: BeanEmptyState(),
                  ),
                ),
                const SizedBox(height: 20),
                const _Label('其他组件'),
                const SizedBox(height: 8),
                Row(
                  children: [
                    _Chip('标签 chip', color: BeanColors.gold),
                    const SizedBox(width: 8),
                    _Chip('警示 chip', color: BeanColors.alertRed),
                    const SizedBox(width: 8),
                    _Chip('中性 chip', color: BeanColors.textSecondaryLight),
                  ],
                ),
              ],
            ),
          ),

          // ── 图表 ─────────────────────────────────────
          _Section(
            title: '图表',
            subtitle: '环形图 / 折线面积 / 排行条',
            child: Column(
              children: [
                SizedBox(
                  height: 150,
                  child: PieChart(
                    PieChartData(
                      sectionsSpace: 3,
                      centerSpaceRadius: 46,
                      startDegreeOffset: -90,
                      sections: [
                        for (final stat in demoCategoryStats)
                          PieChartSectionData(
                            value: stat.value,
                            color: palette.chartColors[stat.categoryIndex],
                            radius: 18,
                            showTitle: false,
                          ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  height: 90,
                  child: LineChart(
                    LineChartData(
                      minX: 0,
                      maxX: 6,
                      minY: 0,
                      gridData: FlGridData(show: false),
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
                          sideTitles: SideTitles(showTitles: false),
                        ),
                      ),
                      lineTouchData: LineTouchData(enabled: false),
                      lineBarsData: [
                        LineChartBarData(
                          spots: const [
                            FlSpot(0, 30),
                            FlSpot(1, 55),
                            FlSpot(2, 42),
                            FlSpot(3, 70),
                            FlSpot(4, 58),
                            FlSpot(5, 88),
                            FlSpot(6, 76),
                          ],
                          isCurved: true,
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

          // ── 暗色预览 ─────────────────────────────────
          _Section(
            title: '暗色模式预览',
            subtitle: '暖黑背景 + 金色点缀',
            child: Theme(
              data: buildBeanTheme(Brightness.dark),
              child: Builder(
                builder: (darkContext) {
                  final darkPalette = BeanPalette.of(darkContext);
                  return Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: BeanColors.bgDark,
                      borderRadius: BorderRadius.circular(BeanRadius.card),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '本月支出',
                          style: TextStyle(
                            fontSize: 12,
                            color: darkPalette.textSecondary,
                          ),
                        ),
                        const SizedBox(height: 6),
                        AmountText(
                          3280.4,
                          showSign: false,
                          fontSize: 28,
                          fontWeight: FontWeight.w700,
                          color: BeanColors.gold,
                        ),
                        const SizedBox(height: 14),
                        Container(
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: BeanColors.surfaceDark,
                            borderRadius: BorderRadius.circular(BeanRadius.card),
                          ),
                          child: Row(
                            children: [
                              const CategoryAvatar(categoryIndex: 0, size: 34),
                              const SizedBox(width: 10),
                              const Expanded(
                                child: Text(
                                  '楼下豆浆油条',
                                  style: TextStyle(
                                    fontSize: 14,
                                    color: BeanColors.textDark,
                                  ),
                                ),
                              ),
                              AmountText(
                                8.5,
                                fontSize: 14,
                                color: BeanColors.textDark,
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ───────────────────────────────────────────────────────────
// 小组件
// ───────────────────────────────────────────────────────────

class _Section extends StatelessWidget {
  const _Section({
    required this.title,
    required this.subtitle,
    required this.child,
  });

  final String title;
  final String subtitle;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final palette = BeanPalette.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: BeanSpace.section),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 2),
          Text(
            subtitle,
            style: TextStyle(fontSize: 12, color: palette.textSecondary),
          ),
          const SizedBox(height: 12),
          BeanCard(child: child),
        ],
      ),
    );
  }
}

class _Label extends StatelessWidget {
  const _Label(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final palette = BeanPalette.of(context);
    return Text(
      text,
      style: TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w600,
        color: palette.textSecondary,
      ),
    );
  }
}

class _Swatch extends StatelessWidget {
  const _Swatch(this.color, this.name, this.hex);

  final Color color;
  final String name;
  final String hex;

  @override
  Widget build(BuildContext context) {
    final palette = BeanPalette.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 74,
          height: 48,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: palette.border),
          ),
        ),
        const SizedBox(height: 4),
        SizedBox(
          width: 74,
          child: Text(name, style: const TextStyle(fontSize: 10)),
        ),
        SizedBox(
          width: 74,
          child: Text(
            hex,
            style: TextStyle(fontSize: 9, color: palette.textSecondary),
          ),
        ),
      ],
    );
  }
}

class _SemanticRow extends StatelessWidget {
  const _SemanticRow({required this.label, required this.child});

  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final palette = BeanPalette.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          SizedBox(
            width: 56,
            child: Text(
              label,
              style: TextStyle(
                fontSize: 12,
                color: palette.textSecondary,
              ),
            ),
          ),
          child,
        ],
      ),
    );
  }
}

class _RadiusCard extends StatelessWidget {
  const _RadiusCard(this.radius, this.label);

  final double radius;
  final String label;

  @override
  Widget build(BuildContext context) {
    final palette = BeanPalette.of(context);
    return Column(
      children: [
        Container(
          width: 68,
          height: 56,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: BeanColors.gold.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(radius),
          ),
          child: Text(
            '$label px',
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: BeanColors.goldDeep,
            ),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'r=$label',
          style: TextStyle(fontSize: 10, color: palette.textSecondary),
        ),
      ],
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip(this.text, {required this.color});

  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(BeanRadius.chip),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: color,
        ),
      ),
    );
  }
}

class _AmountSpecimen extends StatelessWidget {
  const _AmountSpecimen();

  @override
  Widget build(BuildContext context) {
    final palette = BeanPalette.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          formatMoney(1234567.89),
          style: const TextStyle(
            fontSize: 26,
            fontWeight: FontWeight.w700,
            fontFeatures: [FontFeature.tabularFigures()],
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'tabular figures + 千分位：1,234,567.89',
          style: TextStyle(fontSize: 11, color: palette.textSecondary),
        ),
      ],
    );
  }
}
