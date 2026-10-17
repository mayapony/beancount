import 'package:flutter/material.dart';

import '../theme/tokens.dart';
import '../widgets/bean_bottom_nav.dart';
import '../widgets/bean_fab.dart';
import '../widgets/common.dart';
import 'ai_page.dart';
import 'assets_page.dart';
import 'insights_page.dart';
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
    AiPage(),
  ];

  void _openQuickAdd() {
    final palette = BeanPalette.of(context);
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      backgroundColor: palette.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetContext) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '记一笔',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 4),
            Text(
              '3 秒记完，剩下的交给金豆',
              style: TextStyle(fontSize: 12, color: palette.textSecondary),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: _QuickOption(
                    icon: Icons.edit_note_rounded,
                    label: '手动记账',
                    onTap: () => _notYet(sheetContext, '手动记账'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _QuickOption(
                    icon: Icons.photo_camera_rounded,
                    label: '截图记账',
                    onTap: () => _notYet(sheetContext, '截图记账'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _QuickOption(
                    icon: Icons.swap_horiz_rounded,
                    label: '转账',
                    onTap: () => _notYet(sheetContext, '转账'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _notYet(BuildContext sheetContext, String name) {
    Navigator.of(sheetContext).pop();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('$name 将在 M3 实现')),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(index: _index, children: _pages),
      floatingActionButton: BeanFab(onPressed: _openQuickAdd),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerDocked,
      bottomNavigationBar: BeanBottomNav(
        index: _index,
        onTap: (i) => setState(() => _index = i),
      ),
    );
  }
}

class _QuickOption extends StatelessWidget {
  const _QuickOption({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = BeanPalette.of(context);
    return BeanCard(
      onTap: onTap,
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: Column(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: BeanColors.gold.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: BeanColors.goldDeep, size: 22),
          ),
          const SizedBox(height: 8),
          Text(
            label,
            style: TextStyle(fontSize: 13, color: palette.transfer),
          ),
        ],
      ),
    );
  }
}
