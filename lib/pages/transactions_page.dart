import 'package:flutter/material.dart';

import '../data/demo_data.dart';
import '../theme/tokens.dart';
import '../utils/money.dart';
import '../widgets/common.dart';
import 'design_showcase_page.dart';

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

    return SafeArea(
      bottom: false,
      child: ListView(
        padding: const EdgeInsets.only(bottom: 120),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(BeanSpace.page, 12, 8, 10),
            child: Row(
              children: [
                const Text(
                  '金豆',
                  style: TextStyle(fontSize: 24, fontWeight: FontWeight.w700),
                ),
                const SizedBox(width: 10),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: BeanColors.gold.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(BeanRadius.chip),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text(
                        '2026年10月',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: BeanColors.goldDeep,
                        ),
                      ),
                      const Icon(
                        Icons.keyboard_arrow_down_rounded,
                        size: 16,
                        color: BeanColors.goldDeep,
                      ),
                    ],
                  ),
                ),
                const Spacer(),
                IconButton(
                  tooltip: '设计规范',
                  icon: const Icon(Icons.grid_view_rounded),
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => const DesignShowcasePage(),
                    ),
                  ),
                ),
              ],
            ),
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
                      child: AmountText(totalExpense, fontSize: 20),
                    ),
                  ),
                  _divider(palette),
                  Expanded(
                    child: _Metric(
                      label: '收入',
                      child: AmountText(
                        totalIncome,
                        isIncome: true,
                        fontSize: 20,
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
                        fontSize: 20,
                        color: BeanColors.goldDeep,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: BeanSpace.section),

          // ── 明细列表 ──────────────────────────────────────
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
                                height: 1,
                                indent: 68,
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
      padding: const EdgeInsets.symmetric(
        horizontal: BeanSpace.card,
        vertical: 12,
      ),
      child: Row(
        children: [
          CategoryAvatar(categoryIndex: item.categoryIndex),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.title,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '${BeanColors.categoryNames[item.categoryIndex]} · ${item.time}',
                  style: TextStyle(fontSize: 12, color: palette.textSecondary),
                ),
              ],
            ),
          ),
          AmountText(
            item.amount,
            isIncome: item.isIncome,
            fontSize: 15,
          ),
        ],
      ),
    );
  }
}
