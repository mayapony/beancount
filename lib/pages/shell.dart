import 'package:flutter/material.dart';

import '../theme/tokens.dart';
import '../utils/dates.dart';
import '../utils/money.dart';
import '../widgets/bean_bottom_nav.dart';
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

  /// 上次记账的分类/类型/账户：下次打开面板直接继承（DESIGN.md §9.1）。
  int _lastCategory = 0;
  bool _lastIsIncome = false;
  String? _lastAccount;

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
      // 拖拽条由面板自己画（暖灰），不用 Material 默认的冷灰
      showDragHandle: false,
      backgroundColor: palette.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (_) => QuickEntrySheet(
        initialCategory: _lastCategory,
        initialIsIncome: _lastIsIncome,
        initialAccount: _lastAccount,
        onSubmit: (draft) {
          _lastCategory = draft.categoryIndex;
          _lastIsIncome = draft.isIncome;
          _lastAccount = draft.account;
          final detail = <String>[
            draft.account,
            formatEntryTime(draft.time),
            if (draft.note.isNotEmpty) draft.note,
            if (draft.tags.isNotEmpty) draft.tags.map((t) => '#$t').join(' '),
          ];
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                '已记一笔 ${draft.isIncome ? '收入' : '支出'} · '
                '${BeanColors.categoryNames[draft.categoryIndex]} · '
                '¥${formatMoney(draft.amount)}'
                '${detail.isEmpty ? '' : ' · ${detail.join(' · ')}'}'
                '（M3 落库）',
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
      // 金豆由底栏自己绘制（见 BeanBottomNav）：Scaffold 的 FAB 会被底栏盖住投影
      bottomNavigationBar: BeanBottomNav(
        index: _index,
        onTap: (i) => setState(() => _index = i),
        onFabTap: _openQuickEntry,
      ),
    );
  }
}
