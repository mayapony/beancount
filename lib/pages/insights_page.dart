import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../data/db/app_database.dart';
import '../data/repositories/attachment_repository.dart';
import '../data/repositories/insights_repository.dart';
import '../data/repositories/transaction_repository.dart';
import '../theme/tokens.dart';
import '../utils/money.dart';
import '../widgets/common.dart';
import 'category_ledger_page.dart';

/// 洞察页：金额即标题，下面是分类占比、趋势、排行。
class InsightsPage extends StatefulWidget {
  const InsightsPage({
    super.key,
    required this.repository,
    this.transactions,
    this.attachments,
    this.categories = const <Category>[],
    this.refreshSignal,
  });

  final InsightsRepository repository;

  /// 分类下钻要读交易与附件；为空时下钻入口不出现。
  final TransactionRepository? transactions;
  final AttachmentRepository? attachments;
  final List<Category> categories;

  /// 外部写入后的重查信号，语义同 [TransactionsPage.refreshSignal]。
  final Listenable? refreshSignal;

  @override
  State<InsightsPage> createState() => _InsightsPageState();
}

class _InsightsPageState extends State<InsightsPage> {
  InsightsPeriod _period = InsightsPeriod.month;
  late Stream<RangeInsights> _stream = widget.repository.watch(period: _period);

  @override
  void initState() {
    super.initState();
    widget.refreshSignal?.addListener(_reloadFromScratch);
  }

  @override
  void dispose() {
    widget.refreshSignal?.removeListener(_reloadFromScratch);
    super.dispose();
  }

  void _reloadFromScratch() {
    if (!mounted) return;
    setState(() => _stream = widget.repository.watch(period: _period));
  }

  void _select(InsightsPeriod period) {
    if (period == _period) return;
    setState(() {
      _period = period;
      _stream = widget.repository.watch(period: period);
    });
  }

  /// 从分类汇总进入该分类的账目（含二级分类，期间与洞察页一致）。
  void _drillDown(RangeInsights data, Category category) {
    final transactions = widget.transactions;
    if (transactions == null) return;

    final now = DateTime.now();
    final (from, to) = switch (_period) {
      InsightsPeriod.month => (
          DateTime(now.year, now.month),
          DateTime(now.year, now.month + 1),
        ),
      InsightsPeriod.year => (DateTime(now.year), DateTime(now.year + 1)),
      InsightsPeriod.all => (null, null),
    };
    final share = data.expenseCents == 0
        ? null
        : data.categories
                .where((c) => c.category.id == category.id)
                .map((c) => c.cents / data.expenseCents)
                .firstOrNull;

    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => CategoryLedgerPage(
          category: category,
          repository: transactions,
          attachments: widget.attachments,
          categories: widget.categories,
          from: from,
          to: to,
          rangeLabel: data.rangeLabel,
          shareOfPeriod: share,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<RangeInsights>(
      stream: _stream,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return const SafeArea(
            bottom: false,
            child: BeanEmptyState(
              title: '数据暂时打不开',
              subtitle: '本地数据库没准备好，重启 App 再试',
            ),
          );
        }
        final data = snapshot.data;
        if (data == null) return const SizedBox.shrink();
        return _InsightsBody(
          data: data,
          period: _period,
          onSelect: _select,
          onDrillDown: widget.transactions == null
              ? null
              : (category) => _drillDown(data, category),
        );
      },
    );
  }
}

class _InsightsBody extends StatelessWidget {
  const _InsightsBody({
    required this.data,
    required this.period,
    required this.onSelect,
    this.onDrillDown,
  });

  final RangeInsights data;
  final InsightsPeriod period;
  final ValueChanged<InsightsPeriod> onSelect;

  /// 点分类进入下钻；为空时（没有交易仓储）不可点。
  final ValueChanged<Category>? onDrillDown;

  @override
  Widget build(BuildContext context) {
    final palette = BeanPalette.of(context);
    final total = data.expenseCents / 100;

    return SafeArea(
      bottom: false,
      child: ListView(
        padding: const EdgeInsets.only(bottom: 120),
        children: [
          // 金额即标题：先给结论，再给图表
          BeanLargeTitle(
            title: '¥${formatMoney(total)}',
            subtitle:
                '${data.rangeLabel}支出 · 日均 ${formatMoneyCompact(data.dailyAverage)}',
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(
              BeanSpace.page,
              0,
              BeanSpace.page,
              18,
            ),
            child: _CapsuleSwitcher(
              options: const ['月', '年', '全部'],
              index: period.index,
              onTap: (i) => onSelect(InsightsPeriod.values[i]),
            ),
          ),

          const SizedBox(height: 4),

          if (data.categories.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: BeanSpace.page),
              child: BeanEmptyState(
                title: '这段时间还没有支出',
                subtitle: '记一笔，就能看到分类占比',
              ),
            )
          else ...[
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
                                for (final item in data.categories)
                                  PieChartSectionData(
                                    value: item.cents.toDouble(),
                                    color: chartColorOf(item.category, palette),
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
                                '${data.rangeLabel}支出',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: palette.textSecondary,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                formatMoney(total),
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
                        for (final item in data.categories)
                          GestureDetector(
                            onTap: onDrillDown == null
                                ? null
                                : () => onDrillDown!(item.category),
                            child: _LegendItem(
                              color: chartColorOf(item.category, palette),
                              name: item.category.name,
                              value: item.cents / 100,
                              total: total,
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: BeanSpace.section),

            // ── 趋势（折线 + 渐变面积） ────────────────────
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: BeanSpace.page),
              child: BeanCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SectionTitle(
                      '${data.rangeLabel}趋势',
                      trailing: Text(
                        '日均 ${formatMoneyCompact(data.dailyAverage)}',
                        style: TextStyle(
                          fontSize: 12,
                          color: palette.textSecondary,
                        ),
                      ),
                    ),
                    SizedBox(
                      height: 170,
                      child: _TrendChart(
                        points: data.trend,
                        labelStep: data.trend.length > 12 ? 7 : 1,
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
                    for (final item in data.categories)
                      InkWell(
                        borderRadius: BorderRadius.circular(10),
                        onTap: onDrillDown == null
                            ? null
                            : () => onDrillDown!(item.category),
                        child: Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: Row(
                            children: [
                            CategoryAvatar(
                              name: item.category.name,
                              colorValue: item.category.color,
                              iconKey: item.category.icon,
                              size: 32,
                            ),
                            const SizedBox(width: 10),
                            SizedBox(
                              width: 52,
                              child: Text(
                                item.category.name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(fontSize: 13),
                              ),
                            ),
                            Expanded(
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(999),
                                child: LinearProgressIndicator(
                                  value: total == 0 ? 0 : item.cents / 100 / total,
                                  minHeight: 8,
                                  backgroundColor: chartColorOf(
                                    item.category,
                                    palette,
                                  ).withValues(alpha: 0.12),
                                  valueColor: AlwaysStoppedAnimation<Color>(
                                    chartColorOf(item.category, palette),
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 10),
                              SizedBox(
                                width: 72,
                                child: Text(
                                  formatMoneyCompact(item.cents / 100),
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
                      ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// 图表用色：把分类色向表面色混合，降低饱和度，贴合暖金基调。
Color chartColorOf(Category category, BeanPalette palette) =>
    Color.lerp(Color(category.color), palette.surface, 0.28) ??
    Color(category.color);

class _TrendChart extends StatelessWidget {
  const _TrendChart({required this.points, required this.labelStep});

  final List<TrendPoint> points;

  /// 每多少个点标一次横轴文字，避免末尾叠字。
  final int labelStep;

  @override
  Widget build(BuildContext context) {
    final palette = BeanPalette.of(context);
    final maxY = points.fold<int>(0, (m, p) => p.cents > m ? p.cents : m);
    final step = maxY <= 0 ? 50.0 : (maxY / 100).ceil() * 25.0;

    return LineChart(
      LineChartData(
        minX: 0,
        maxX: (points.length - 1).clamp(1, 99999).toDouble(),
        minY: 0,
        gridData: FlGridData(
          show: true,
          drawVerticalLine: false,
          horizontalInterval: step,
          getDrawingHorizontalLine: (v) => FlLine(
            color: palette.border,
            strokeWidth: 1,
          ),
        ),
        borderData: FlBorderData(show: false),
        titlesData: FlTitlesData(
          leftTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
          rightTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
          topTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              interval: labelStep.toDouble(),
              reservedSize: 22,
              getTitlesWidget: (value, meta) {
                final i = value.round();
                if (i < 0 || i >= points.length) return const SizedBox.shrink();
                if (i % labelStep != 0) return const SizedBox.shrink();
                return Text(
                  points[i].label,
                  style: TextStyle(
                    fontSize: 10,
                    color: palette.textSecondary,
                  ),
                );
              },
            ),
          ),
        ),
        lineTouchData: LineTouchData(enabled: false),
        lineBarsData: [
          LineChartBarData(
            spots: [
              for (var i = 0; i < points.length; i++)
                FlSpot(i.toDouble(), points[i].cents / 100),
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
          total == 0 ? '0%' : '${(value / total * 100).round()}%',
          style: TextStyle(fontSize: 12, color: palette.textSecondary),
        ),
      ],
    );
  }
}

class _CapsuleSwitcher extends StatelessWidget {
  const _CapsuleSwitcher({
    required this.options,
    required this.index,
    required this.onTap,
  });

  final List<String> options;
  final int index;
  final ValueChanged<int> onTap;

  @override
  Widget build(BuildContext context) {
    final palette = BeanPalette.of(context);
    // 分段控件：砂色轨道 + 白色胶囊，不用金色底（金色留给选中分类与主按钮）
    return Container(
      height: 36,
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: palette.neutral.track,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          for (var i = 0; i < options.length; i++)
            Expanded(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => onTap(i),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 160),
                  decoration: BoxDecoration(
                    color: index == i
                        ? palette.neutral.raised
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    options[i],
                    style: TextStyle(
                      fontSize: 13,
                      letterSpacing: -0.1,
                      fontWeight:
                          index == i ? FontWeight.w600 : FontWeight.w500,
                      color: index == i
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
