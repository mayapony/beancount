import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../data/demo_data.dart';
import '../theme/tokens.dart';
import '../utils/money.dart';
import '../widgets/common.dart';

class AssetsPage extends StatelessWidget {
  const AssetsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final palette = BeanPalette.of(context);
    final assets = demoAccounts
        .where((a) => a.balance > 0)
        .fold<double>(0, (s, a) => s + a.balance);
    final debts = demoAccounts
        .where((a) => a.balance < 0)
        .fold<double>(0, (s, a) => s + a.balance.abs());
    final netWorth = assets - debts;

    return SafeArea(
      bottom: false,
      child: ListView(
        padding: const EdgeInsets.only(bottom: 120),
        children: [
          // 标题就是净资产本身：一个数字承担定位 + 层级 + 锚点
          BeanLargeTitle(
            title: '¥${formatMoney(netWorth)}',
            subtitle: '净资产 · 共 ${demoAccounts.length} 个账户',
          ),

          // ── 资产构成 + 走势 ────────────────────────────────
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: BeanSpace.page),
            child: BeanCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: _SubMetric(
                          label: '总资产',
                          child: _Money(
                            value: assets,
                            color: palette.income,
                          ),
                        ),
                      ),
                      Container(
                          width: BeanSpace.hairline,
                          height: 30,
                          color: palette.border),
                      const SizedBox(width: 16),
                      Expanded(
                        child: _SubMetric(
                          label: '总负债',
                          child: _Money(value: debts),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  SizedBox(
                    height: 64,
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
                              FlSpot(0, 22000),
                              FlSpot(1, 23500),
                              FlSpot(2, 22800),
                              FlSpot(3, 26000),
                              FlSpot(4, 27200),
                              FlSpot(5, 28100),
                              FlSpot(6, 29520),
                            ],
                            isCurved: true,
                            color: BeanColors.beanGreenDeep,
                            barWidth: 2.5,
                            isStrokeCapRound: true,
                            dotData: FlDotData(show: false),
                            belowBarData: BarAreaData(
                              show: true,
                              gradient: LinearGradient(
                                begin: Alignment.topCenter,
                                end: Alignment.bottomCenter,
                                colors: [
                                  BeanColors.beanGreen.withValues(alpha: 0.22),
                                  BeanColors.beanGreen.withValues(alpha: 0.02),
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

          // ── 账户列表 ─────────────────────────────────────
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: BeanSpace.page),
            child: BeanCard(
              padding: EdgeInsets.zero,
              child: Column(
                children: [
                  for (var i = 0; i < demoAccounts.length; i++) ...[
                    _AccountRow(account: demoAccounts[i]),
                    if (i != demoAccounts.length - 1)
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

          const SizedBox(height: BeanSpace.section),

          // ── 信用卡还款提醒（红色仅用于警示） ──────────────
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: BeanSpace.page),
            child: BeanCard(
              child: Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: BeanColors.alertRed.withValues(alpha: 0.10),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.notifications_active_rounded,
                      size: 20,
                      color: BeanColors.alertRedDeep,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          '招行信用卡 8 天后到期',
                          style: TextStyle(
                            fontSize: 17,
                            letterSpacing: -0.2,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '本期应还 3,280.40',
                          style: TextStyle(
                            fontSize: 12,
                            color: palette.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 5,
                    ),
                    decoration: BoxDecoration(
                      color: BeanColors.alertRed.withValues(alpha: 0.10),
                      borderRadius: BorderRadius.circular(BeanRadius.chip),
                    ),
                    child: const Text(
                      '待还款',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: BeanColors.alertRedDeep,
                      ),
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
  const _AccountRow({required this.account});

  final DemoAccount account;

  @override
  Widget build(BuildContext context) {
    final palette = BeanPalette.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: 16,
        vertical: 11,
      ),
      child: Row(
        children: [
          CategoryAvatar(categoryIndex: account.categoryIndex),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  account.name,
                  style: const TextStyle(
                    fontSize: 17,
                    height: 1.25,
                    letterSpacing: -0.2,
                    fontWeight: FontWeight.w400,
                  ),
                ),
                const SizedBox(height: 1),
                Text(
                  account.isCredit
                      ? '${account.type} · ${account.dueDay} 日还款'
                      : account.type,
                  style: TextStyle(
                    fontSize: 13,
                    height: 1.2,
                    color: palette.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          // 余额用「符号 + ¥ + 两位小数」：欠款是 -¥3,280.40，不是没有符号的 3,280.40
          _Money(
            value: account.balance,
            color: account.balance < 0 ? palette.alert : null,
            signed: true,
          ),
        ],
      ),
    );
  }
}

/// 带货币符号的金额：`-¥3,280.40` / `¥1,240.55`。
class _Money extends StatelessWidget {
  const _Money({
    required this.value,
    this.color,
    this.signed = false,
  });

  final double value;
  final Color? color;

  /// 保留参数只为语义清楚：负数一律带 `-`，正数不加 `+`（余额不是收支）
  final bool signed;

  @override
  Widget build(BuildContext context) {
    final negative = value < 0;
    return Text(
      '${negative ? '-' : ''}¥${formatMoney(value.abs())}',
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
