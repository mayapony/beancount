import 'package:flutter/material.dart';

import '../theme/tokens.dart';
import '../utils/money.dart';
import '../widgets/bean_bottom_nav.dart';
import '../widgets/bean_fab.dart';
import '../widgets/quick_entry_sheet.dart';
import 'assets_page.dart';
import 'insights_page.dart';
import 'settings_page.dart';
import 'transactions_page.dart';

class ShellPage extends StatefulWidget {
  const ShellPage({super.key});

  @override
  State<ShellPage> createState() => _ShellPageState();
}

class _ShellPageState extends State<ShellPage> {
  int _index = 0;

  static const _pages = <Widget>[
    TransactionsPage(),
    InsightsPage(),
    AssetsPage(),
    SettingsPage(),
  ];

  /// 金豆按下 → 一次点击直接进入金额输入（不再有多级菜单）。
  void _openQuickEntry() {
    final palette = BeanPalette.of(context);
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: palette.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => QuickEntrySheet(
        onSubmit: (amount, isIncome, categoryIndex) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                '已记一笔 ${isIncome ? '收入' : '支出'} · '
                '${BeanColors.categoryNames[categoryIndex]} · '
                '¥${formatMoney(amount)}（M3 落库）',
              ),
            ),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(index: _index, children: _pages),
      floatingActionButton: BeanFab(onPressed: _openQuickEntry),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerDocked,
      bottomNavigationBar: BeanBottomNav(
        index: _index,
        onTap: (i) => setState(() => _index = i),
      ),
    );
  }
}
