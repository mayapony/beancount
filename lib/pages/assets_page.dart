import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../data/db/enums.dart';
import '../data/repositories/account_repository.dart';
import '../data/repositories/net_worth_repository.dart';
import '../theme/tokens.dart';
import '../utils/money.dart';
import '../widgets/common.dart';

/// 资产页：净资产即标题，下面按账户列出余额。
///
/// 余额**全部由交易推导**（初始余额 + 收入 − 支出），不存冗余字段，
/// 所以删账、改账都不会让数字漂移。
class AssetsPage extends StatefulWidget {
  const AssetsPage({
    super.key,
    required this.repository,
    this.netWorth,
  });

  final AccountRepository repository;

  /// 净资产走势（由账目推导）；为空时只显示账户列表。
  final NetWorthRepository? netWorth;

  @override
  State<AssetsPage> createState() => _AssetsPageState();
}

class _AssetsPageState extends State<AssetsPage> {
  late final Stream<List<AccountBalance>> _stream =
      widget.repository.watchWithBalances();

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<AccountBalance>>(
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
        final accounts = snapshot.data;
        if (accounts == null) return const SizedBox.shrink();
        if (accounts.isEmpty) {
          return const SafeArea(
            bottom: false,
            child: BeanEmptyState(
              title: '还没有账户',
              subtitle: '记一笔时会自动使用默认账户',
            ),
          );
        }
        return _AssetsBody(accounts: accounts, netWorth: widget.netWorth);
      },
    );
  }
}

class _AssetsBody extends StatefulWidget {
  const _AssetsBody({required this.accounts, this.netWorth});

  final List<AccountBalance> accounts;
  final NetWorthRepository? netWorth;

  @override
  State<_AssetsBody> createState() => _AssetsBodyState();
}

class _AssetsBodyState extends State<_AssetsBody> {
  NetWorthRange _range = NetWorthRange.sixMonths;
  Stream<NetWorthSeries>? _seriesStream;

  List<AccountBalance> get accounts => widget.accounts;

  @override
  void initState() {
    super.initState();
    _seriesStream = widget.netWorth?.watch(range: _range);
  }

  void _pickRange(NetWorthRange range) {
    if (range == _range) return;
    setState(() {
      _range = range;
      _seriesStream = widget.netWorth?.watch(range: _range);
    });
  }

  @override
  Widget build(BuildContext context) {
    final palette = BeanPalette.of(context);

    final totalAssets = accounts
        .where((a) => a.balanceCents > 0)
        .fold<int>(0, (sum, a) => sum + a.balanceCents);
    final totalDebts = accounts
        .where((a) => a.balanceCents < 0)
        .fold<int>(0, (sum, a) => sum + a.balanceCents.abs());
    final netWorth = totalAssets - totalDebts;

    return SafeArea(
      bottom: false,
      child: ListView(
        padding: const EdgeInsets.only(bottom: 120),
        children: [
          // 标题就是净资产本身：一个数字承担定位 + 层级 + 锚点
          BeanLargeTitle(
            title: _signed(netWorth),
            subtitle: '净资产 · 共 ${accounts.length} 个账户',
          ),

          // ── 资产构成 ──────────────────────────────────────
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: BeanSpace.page),
            child: BeanCard(
              child: Row(
                children: [
                  Expanded(
                    child: _SubMetric(
                      label: '总资产',
                      child: _Money(
                        cents: totalAssets,
                        color: palette.income,
                      ),
                    ),
                  ),
                  Container(
                    width: BeanSpace.hairline,
                    height: 30,
                    color: palette.border,
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: _SubMetric(
                      label: '总负债',
                      child: _Money(
                        cents: -totalDebts,
                        color: totalDebts > 0 ? palette.alert : null,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: BeanSpace.section),

          // ── 净资产走势（由账目推导，不加快照表）────────────
          if (_seriesStream != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: BeanSpace.page),
              child: BeanCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Text(
                          '净资产走势',
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const Spacer(),
                        for (final range in NetWorthRange.values)
                          Padding(
                            padding: const EdgeInsets.only(left: 6),
                            child: _RangeChip(
                              label: range.label,
                              selected: _range == range,
                              onTap: () => _pickRange(range),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    StreamBuilder<NetWorthSeries>(
                      stream: _seriesStream,
                      builder: (context, snapshot) {
                        final series = snapshot.data;
                        if (series == null) {
                          return const SizedBox(height: 120);
                        }
                        if (series.isEmpty) {
                          return Padding(
                            padding: const EdgeInsets.symmetric(vertical: 28),
                            child: Text(
                              '还没有足够的数据',
                              style: TextStyle(
                                fontSize: 13,
                                color: palette.textSecondary,
                              ),
                            ),
                          );
                        }
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Text(
                                  '${series.changeCents >= 0 ? '+' : '-'}'
                                  '${formatMoney(series.changeCents.abs() / 100)}',
                                  style: TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w600,
                                    color: series.changeCents >= 0
                                        ? palette.income
                                        : palette.alert,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  '较 ${series.points.first.label}',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: palette.textSecondary,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            SizedBox(
                              height: 132,
                              child: _NetWorthChart(series: series),
                            ),
                          ],
                        );
                      },
                    ),
                  ],
                ),
              ),
            ),

          const SizedBox(height: BeanSpace.section),

          // ── 账户列表 ─────────────────────────────────────
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: BeanSpace.page),
            child: BeanCard(
              padding: EdgeInsets.zero,
              child: Column(
                children: [
                  for (var i = 0; i < accounts.length; i++) ...[
                    _AccountRow(item: accounts[i]),
                    if (i != accounts.length - 1)
                      Divider(
                        height: BeanSpace.hairline,
                        thickness: BeanSpace.hairline,
                        indent: 62,
                        color: palette.border,
                      ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 负号放在 ¥ 前面：`-¥38.50` 读作"欠了 38.50"。
String _signed(int cents) =>
    '${cents < 0 ? '-' : ''}¥${formatMoney(cents.abs() / 100)}';

class _SubMetric extends StatelessWidget {
  const _SubMetric({required this.label, required this.child});

  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final palette = BeanPalette.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(fontSize: 11, color: palette.textSecondary),
        ),
        const SizedBox(height: 4),
        child,
      ],
    );
  }
}

class _AccountRow extends StatelessWidget {
  const _AccountRow({required this.item});

  final AccountBalance item;

  @override
  Widget build(BuildContext context) {
    final palette = BeanPalette.of(context);
    final account = item.account;
    final count = item.count;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
      child: Row(
        children: [
          _AccountAvatar(type: account.type),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  account.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 17,
                    height: 1.25,
                    letterSpacing: -0.2,
                    fontWeight: FontWeight.w400,
                  ),
                ),
                const SizedBox(height: 1),
                Text(
                  count == 0
                      ? '${_typeLabel(account.type)} · 还没有记账'
                      : '${_typeLabel(account.type)} · $count 笔',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13,
                    height: 1.2,
                    color: palette.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          // 余额用「符号 + ¥ + 两位小数」：欠款是 -¥3,280.40
          _Money(
            cents: item.balanceCents,
            color: item.balanceCents < 0 ? palette.alert : null,
          ),
        ],
      ),
    );
  }

  static String _typeLabel(AccountType type) {
    switch (type) {
      case AccountType.wallet:
        return '钱包';
      case AccountType.debit:
        return '储蓄卡';
      case AccountType.credit:
        return '信用卡';
      case AccountType.other:
        return '其他';
    }
  }
}

/// 账户头像：实心圆 + 白色字形，颜色按账户类型固定，方便扫视。
class _AccountAvatar extends StatelessWidget {
  const _AccountAvatar({required this.type});

  final AccountType type;

  @override
  Widget build(BuildContext context) {
    final (color, icon) = switch (type) {
      AccountType.wallet => (BeanColors.gold, Icons.account_balance_wallet_rounded),
      AccountType.debit => (const Color(0xFF3B82F6), Icons.credit_card_rounded),
      AccountType.credit => (const Color(0xFF8B5CF6), Icons.credit_score_rounded),
      AccountType.other => (const Color(0xFF64748B), Icons.savings_rounded),
    };
    return Container(
      width: 30,
      height: 30,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      child: Icon(icon, size: 16, color: Colors.white),
    );
  }
}

/// 带货币符号的金额：`-¥3,280.40` / `¥1,240.55`。
class _Money extends StatelessWidget {
  const _Money({required this.cents, this.color});

  final int cents;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final negative = cents < 0;
    return Text(
      '${negative ? '-' : ''}¥${formatMoney(cents.abs() / 100)}',
      style: TextStyle(
        fontSize: 17,
        letterSpacing: -0.2,
        fontWeight: FontWeight.w500,
        color: color,
        fontFeatures: const [FontFeature.tabularFigures()],
      ),
    );
  }
}

class _RangeChip extends StatelessWidget {
  const _RangeChip({
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
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: selected ? palette.goldDeep : palette.neutral.sand,
          borderRadius: BorderRadius.circular(7),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 11,
            color: selected
                ? Theme.of(context).colorScheme.onPrimary
                : palette.textSecondary,
          ),
        ),
      ),
    );
  }
}

/// 净值曲线：纵轴不标数字（形状与变化额更重要），并允许负值。
class _NetWorthChart extends StatelessWidget {
  const _NetWorthChart({required this.series});

  final NetWorthSeries series;

  @override
  Widget build(BuildContext context) {
    final palette = BeanPalette.of(context);
    final points = series.points;
    final values = [for (final p in points) p.cents / 100];
    final minValue = values.reduce((a, b) => a < b ? a : b);
    final maxValue = values.reduce((a, b) => a > b ? a : b);
    final span = (maxValue - minValue).abs();
    final padding = span < 1 ? 1.0 : span * 0.15;

    return LineChart(
      LineChartData(
        minX: 0,
        maxX: (points.length - 1).clamp(1, 99999).toDouble(),
        minY: minValue - padding,
        maxY: maxValue + padding,
        gridData: const FlGridData(show: false),
        borderData: FlBorderData(show: false),
        titlesData: FlTitlesData(
          leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 20,
              interval: 1,
              getTitlesWidget: (value, meta) {
                final i = value.round();
                if (i < 0 || i >= points.length) return const SizedBox.shrink();
                // 点太密时隔一个标一次，避免叠字
                if (points.length > 8 && i.isOdd) return const SizedBox.shrink();
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
        lineTouchData: const LineTouchData(enabled: false),
        lineBarsData: [
          LineChartBarData(
            spots: [
              for (var i = 0; i < points.length; i++)
                FlSpot(i.toDouble(), points[i].cents / 100),
            ],
            isCurved: true,
            curveSmoothness: 0.2,
            color: BeanColors.gold,
            barWidth: 3,
            isStrokeCapRound: true,
            dotData: const FlDotData(show: false),
            belowBarData: BarAreaData(
              show: true,
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  BeanColors.gold.withValues(alpha: 0.24),
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
