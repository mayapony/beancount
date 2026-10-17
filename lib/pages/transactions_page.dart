import 'package:flutter/material.dart';

import '../data/demo_data.dart';
import '../theme/tokens.dart';
import '../utils/money.dart';
import '../widgets/common.dart';

class TransactionsPage extends StatelessWidget {
  const TransactionsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final palette = BeanPalette.of(context);

    final totalExpense = demoDayGroups.fold<double>(
      0,
      (sum, g) => sum + g.expense,
    );
    final totalIncome = demoDayGroups.fold<double>(
      0,
      (sum, g) =>
          sum +
          g.items
              .where((t) => t.isIncome)
              .fold<double>(0, (a, t) => a + t.amount),
    );

    final expenseCount = demoDayGroups.fold<int>(
      0,
      (sum, g) => sum + g.items.where((t) => !t.isIncome).length,
    );
    final incomeCount = demoDayGroups.fold<int>(
      0,
      (sum, g) => sum + g.items.where((t) => t.isIncome).length,
    );
    final dailyAvg = totalExpense / 17;

    return SafeArea(
      bottom: false,
      child: ListView(
        padding: const EdgeInsets.only(bottom: 120),
        children: [
          // 没有「明细」标题：月份就是标题，底部 tab 已经说明这是哪一页
          BeanLargeTitle(
            title: '10月',
            subtitle: '2026年 · ${expenseCount + incomeCount} 笔收支',
            actions: [
              BeanCircleAction(
                icon: Icons.calendar_month_rounded,
                tooltip: '切换月份',
                onTap: () {},
              ),
            ],
          ),

          // ── 本月概览 ──────────────────────────────────────
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: BeanSpace.page),
            child: BeanCard(
              child: Row(
                children: [
                  Expanded(
                    child: _Metric(
                      label: '支出',
                      child: AmountText(totalExpense, fontSize: 17),
                    ),
                  ),
                  _divider(palette),
                  Expanded(
                    child: _Metric(
                      label: '收入',
                      child: AmountText(
                        totalIncome,
                        isIncome: true,
                        fontSize: 17,
                      ),
                    ),
                  ),
                  _divider(palette),
                  Expanded(
                    child: _Metric(
                      label: '结余',
                      child: AmountText(
                        totalIncome - totalExpense,
                        showSign: false,
                        fontSize: 17,
                        color: BeanColors.goldDeep,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),

          // 一行细信息：日均 + 笔数（不加卡片，保持轻盈）
          Padding(
            padding: const EdgeInsets.fromLTRB(
              BeanSpace.page,
              10,
              BeanSpace.page,
              0,
            ),
            child: Row(
              children: [
                Icon(
                  Icons.insights_rounded,
                  size: 14,
                  color: palette.textSecondary,
                ),
                const SizedBox(width: 5),
                Text(
                  '日均支出 ${formatMoney(dailyAvg)}',
                  style: TextStyle(
                    fontSize: 12,
                    color: palette.textSecondary,
                  ),
                ),
                const Spacer(),
                Text(
                  '$expenseCount 笔支出 · $incomeCount 笔收入',
                  style: TextStyle(
                    fontSize: 12,
                    color: palette.textSecondary,
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: BeanSpace.section),
          ...demoDayGroups.map(
            (group) => Padding(
              padding: const EdgeInsets.only(bottom: BeanSpace.section),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(
                      BeanSpace.page,
                      0,
                      BeanSpace.page,
                      8,
                    ),
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
                  Padding(
                    padding:
                        const EdgeInsets.symmetric(horizontal: BeanSpace.page),
                    child: BeanCard(
                      padding: EdgeInsets.zero,
                      child: Column(
                        children: [
                          for (var i = 0; i < group.items.length; i++) ...[
                            _TransactionRow(item: group.items[i]),
                            if (i != group.items.length - 1)
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
            ),
          ),
        ],
      ),
    );
  }

  Widget _divider(BeanPalette palette) => Container(
        width: 1,
        height: 34,
        color: palette.border,
      );
}

class _Metric extends StatelessWidget {
  const _Metric({required this.label, required this.child});

  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final palette = BeanPalette.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Text(
          label,
          style: TextStyle(fontSize: 12, color: palette.textSecondary),
        ),
        const SizedBox(height: 6),
        child,
      ],
    );
  }
}

class _TransactionRow extends StatelessWidget {
  const _TransactionRow({required this.item});

  final DemoTransaction item;

  @override
  Widget build(BuildContext context) {
    final palette = BeanPalette.of(context);
    return Padding(
      // 行高 56：iOS 列表的节奏，比原来的 64 更紧凑但留白更多
      padding: const EdgeInsets.symmetric(
        horizontal: 16,
        vertical: 11,
      ),
      child: Row(
        children: [
          CategoryAvatar(categoryIndex: item.categoryIndex),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.title,
                  style: const TextStyle(
                    fontSize: 17,
                    height: 1.25,
                    letterSpacing: -0.2,
                    fontWeight: FontWeight.w400,
                  ),
                ),
                const SizedBox(height: 1),
                Text(
                  '${item.time} · ${BeanColors.categoryNames[item.categoryIndex]}',
                  style: TextStyle(
                    fontSize: 13,
                    height: 1.2,
                    color: palette.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          AmountText(
            item.amount,
            isIncome: item.isIncome,
            fontSize: 17,
            fontWeight: FontWeight.w500,
          ),
        ],
      ),
    );
  }
}
