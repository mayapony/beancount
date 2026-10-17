import 'package:flutter/material.dart';

import '../data/db/app_database.dart';
import '../data/repositories/account_repository.dart';
import '../data/repositories/attachment_repository.dart';
import '../data/repositories/category_repository.dart';
import '../data/repositories/transaction_repository.dart';
import '../theme/tokens.dart';
import '../utils/money.dart';
import '../utils/month.dart';
import '../widgets/common.dart';
import '../widgets/ledger_day_list.dart';
import '../widgets/month_picker_sheet.dart';
import 'search_page.dart';
import 'transaction_detail_page.dart';

/// 明细页：按天分组的交易列表，数据来自本地库（写入后自动刷新）。
///
/// 浏览范围是「一个自然月」：默认当月，切月后重新订阅该月数据。
class TransactionsPage extends StatefulWidget {
  const TransactionsPage({
    super.key,
    required this.repository,
    this.attachments,
    this.categories,
    this.accounts,
    this.initialMonth,
  });

  final TransactionRepository repository;

  /// 附件仓储：用来把库里的文件名还原成磁盘路径，画 32×32 缩略图。
  final AttachmentRepository? attachments;

  /// 分类与账户仓储：进详情页编辑时需要完整的候选列表；为空时详情页只读。
  final CategoryRepository? categories;
  final AccountRepository? accounts;

  /// 初始浏览月份（测试与深链用）；为空时落在当前自然月。
  final LedgerMonth? initialMonth;

  @override
  State<TransactionsPage> createState() => _TransactionsPageState();
}

class _TransactionsPageState extends State<TransactionsPage> {
  late LedgerMonth _month = widget.initialMonth ?? LedgerMonth.current();
  late Stream<LedgerSnapshot> _stream = _watch();

  @override
  void initState() {
    super.initState();
    // 先把附件目录解析好：列表里的缩略图需要同步拿路径
    widget.attachments?.ensureReady();
  }

  @override
  void didUpdateWidget(covariant TransactionsPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    // initialMonth 变化时跟随（测试与深链会换它；正常使用不会变）
    final next = widget.initialMonth;
    if (next != null && next != _month) {
      _month = next;
      _stream = _watch();
    }
  }

  Stream<LedgerSnapshot> _watch() => widget.repository.watchLedger(
        year: _month.year,
        month: _month.month,
      );

  void _showMonth(LedgerMonth month) {
    if (month == _month) return;
    setState(() {
      _month = month;
      _stream = _watch();
    });
  }

  /// 打开搜索页（搜索页自己取候选分类/账户）。
  Future<void> _openSearch() async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => SearchPage(
          repository: widget.repository,
          attachments: widget.attachments,
          categories: widget.categories,
          accounts: widget.accounts,
        ),
      ),
    );
  }

  /// 打开一笔的详情；编辑面板要的候选分类/账户在这里现取，避免列表变旧。
  Future<void> _openRow(TransactionRow row) async {
    final categoryList = widget.categories == null
        ? const <Category>[]
        : await widget.categories!.allCategories();
    final accountList = widget.accounts == null
        ? const <AccountBalance>[]
        : await widget.accounts!.withBalances();
    if (!mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => TransactionDetailPage(
          row: row,
          repository: widget.repository,
          attachments: widget.attachments,
          categories: categoryList,
          accounts: accountList,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<LedgerSnapshot>(
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
        if (data == null) {
          // 首帧还没读到库：留白，不闪"空账本"
          return const SizedBox.shrink();
        }
        if (data.groups.isEmpty) {
          return _EmptyLedger(
            month: _month,
            hasNothingAtAll: data.hasNothingAtAll,
            onBackToCurrent: () => _showMonth(LedgerMonth.current()),
          );
        }
        return _Ledger(
          month: _month,
          groups: data.groups,
          attachments: widget.attachments,
          onPickMonth: _showMonth,
          onOpenRow: _openRow,
          onSearch: _openSearch,
          onSwipeMonth: (delta) =>
              _showMonth(delta > 0 ? _month.next : _month.previous),
        );
      },
    );
  }
}

/// 空状态分两种：整库没有账 vs 当前浏览的月份没有账。
///
/// 后者才给「回到本月」出口——整库空时切月没有意义，只会让用户以为数据丢了。
class _EmptyLedger extends StatelessWidget {
  const _EmptyLedger({
    required this.month,
    required this.hasNothingAtAll,
    required this.onBackToCurrent,
  });

  final LedgerMonth month;
  final bool hasNothingAtAll;
  final VoidCallback onBackToCurrent;

  @override
  Widget build(BuildContext context) {
    if (hasNothingAtAll) {
      return const SafeArea(
        bottom: false,
        child: BeanEmptyState(
          title: '还没有记账',
          subtitle: '点下方的金豆，记下第一笔',
        ),
      );
    }
    return SafeArea(
      bottom: false,
      child: BeanEmptyState(
        title: '这个月还没有记账',
        subtitle: '${month.year}年${month.month}月没有记录',
        icon: Icons.calendar_month_rounded,
        action: month.isCurrent
            ? null
            : TextButton(
                onPressed: onBackToCurrent,
                child: const Text('回到本月'),
              ),
      ),
    );
  }
}

class _Ledger extends StatelessWidget {
  const _Ledger({
    required this.month,
    required this.groups,
    this.attachments,
    required this.onPickMonth,
    required this.onOpenRow,
    required this.onSearch,
    required this.onSwipeMonth,
  });

  final LedgerMonth month;
  final List<DayGroup> groups;
  final AttachmentRepository? attachments;
  final ValueChanged<LedgerMonth> onPickMonth;

  /// 点一行进入详情。
  final ValueChanged<TransactionRow> onOpenRow;

  /// 打开搜索页。
  final VoidCallback onSearch;

  /// 左右滑动切月：+1 下个月，-1 上个月。
  final ValueChanged<int> onSwipeMonth;

  /// 滑动速度阈值（px/s）：低于它按误触处理，免得手指蹭到列表就翻月。
  static const double _swipeVelocity = 200;

  @override
  Widget build(BuildContext context) {
    final palette = BeanPalette.of(context);

    final totalExpense = groups.fold<int>(0, (sum, g) => sum + g.expenseCents);
    final totalIncome = groups.fold<int>(0, (sum, g) => sum + g.incomeCents);
    final expenseCount = groups.fold<int>(
      0,
      (sum, g) => sum + g.items.where((r) => !r.isIncome).length,
    );
    final incomeCount = groups.fold<int>(
      0,
      (sum, g) => sum + g.items.where((r) => r.isIncome).length,
    );
    final activeDays = groups.length;
    final dailyAvg = activeDays == 0 ? 0 : totalExpense / activeDays / 100;

    return SafeArea(
      bottom: false,
      child: GestureDetector(
        // 只对水平拖动生效：垂直滚动仍归 ListView
        onHorizontalDragEnd: (details) {
          final velocity = details.primaryVelocity ?? 0;
          if (velocity.abs() < _swipeVelocity) return;
          onSwipeMonth(velocity < 0 ? 1 : -1);
        },
        child: ListView(
          padding: const EdgeInsets.only(bottom: 120),
          children: [
            // 没有「明细」标题：月份就是标题，底部 tab 已经说明这是哪一页
            BeanLargeTitle(
              title: month.title,
              subtitle: '${month.year}年 · ${expenseCount + incomeCount} 笔收支',
              actions: [
                BeanCircleAction(
                  icon: Icons.search_rounded,
                  tooltip: '搜索账目',
                  onTap: onSearch,
                ),
                const SizedBox(width: 8),
                BeanCircleAction(
                  icon: Icons.calendar_month_rounded,
                  tooltip: '切换月份',
                  onTap: () async {
                    final picked = await MonthPickerSheet.show(
                      context,
                      current: month,
                    );
                    if (picked != null) onPickMonth(picked);
                  },
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
                        child: AmountText(totalExpense / 100, fontSize: 17),
                      ),
                    ),
                    _divider(palette),
                    Expanded(
                      child: _Metric(
                        label: '收入',
                        child: AmountText(
                          totalIncome / 100,
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
                          (totalIncome - totalExpense) / 100,
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
            LedgerDayList(
              groups: groups,
              attachments: attachments,
              onOpen: onOpenRow,
            ),
          ],
        ),
      ),
    );
  }

  Widget _divider(BeanPalette palette) => Container(
        width: 1,
        height: 34,
        color: palette.border,
      );
}class _Metric extends StatelessWidget {
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
