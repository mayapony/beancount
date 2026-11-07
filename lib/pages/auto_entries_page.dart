import 'package:flutter/material.dart';

import '../data/db/app_database.dart';
import '../data/repositories/account_repository.dart';
import '../data/repositories/attachment_repository.dart';
import '../data/repositories/transaction_repository.dart';
import '../services/attachments/image_picker_service.dart';
import '../services/capture/capture_account_map.dart';
import '../services/capture/source_app.dart';
import '../theme/tokens.dart';
import '../utils/dates.dart';
import '../utils/money.dart';
import '../widgets/common.dart';
import 'transaction_detail_page.dart';

/// 「最近自动记账」：事后审计列表。
///
/// 每笔自动入账都在这里出现，用户核对、修改、删除（点进详情）。不做入账前确认，
/// 只在这里补上「看得到、改得了」的持久入口；标题的「今天 N 笔」同时承担
/// 「自动记账还活着吗」的可见性（配合失效心跳提示）。
class AutoEntriesPage extends StatefulWidget {
  const AutoEntriesPage({
    super.key,
    required this.repository,
    this.attachments,
    this.categories = const <Category>[],
    this.accounts = const <AccountBalance>[],
    this.pickImage,
    this.accountMap,
  });

  final TransactionRepository repository;
  final AttachmentRepository? attachments;
  final List<Category> categories;
  final List<AccountBalance> accounts;
  final ImagePickFn? pickImage;

  /// 「包名 + 渠道词 → 账户」的记忆；为空时只补账户、不记忆。
  final CaptureAccountMap? accountMap;

  @override
  State<AutoEntriesPage> createState() => _AutoEntriesPageState();
}

class _AutoEntriesPageState extends State<AutoEntriesPage> {
  List<TransactionRow> _rows = const [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final rows = await widget.repository.recentAutoEntries();
    // 待人工处理的置顶：它们卡着账户没补，用户得先看见。
    final sorted = [
      ...rows.where((row) => row.transaction.needsReview == true),
      ...rows.where((row) => row.transaction.needsReview != true),
    ];
    if (!mounted) return;
    setState(() {
      _rows = sorted;
      _loading = false;
    });
  }

  /// 给待处理的一笔补账户，并把这次选择记成「该应用 + 该渠道」的默认账户。
  Future<void> _assignAccount(TransactionRow row) async {
    final account = await showModalBottomSheet<Account>(
      context: context,
      builder: (context) => _AccountPicker(accounts: widget.accounts),
    );
    if (account == null) return;
    await widget.repository.assignAccountAndClearReview(
      row.transaction.id,
      account.id,
    );
    await widget.accountMap?.remember(
      row.transaction.sourcePackage ?? '',
      row.transaction.sourceChannel,
      account.id,
    );
    await _load();
  }

  int get _todayCount {
    final now = DateTime.now();
    return _rows.where((row) {
      final at = row.transaction.happenedAt;
      return at.year == now.year && at.month == now.month && at.day == now.day;
    }).length;
  }

  Future<void> _open(TransactionRow row) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => TransactionDetailPage(
          row: row,
          repository: widget.repository,
          attachments: widget.attachments,
          categories: widget.categories,
          accounts: widget.accounts,
          pickImage: widget.pickImage,
        ),
      ),
    );
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final palette = BeanPalette.of(context);

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        leading: IconButton(
          tooltip: '返回',
          icon: const Icon(Icons.chevron_left_rounded, size: 28),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: const Text(
          '最近自动记账',
          style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
        ),
        centerTitle: true,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _rows.isEmpty
              ? const _EmptyList()
              : ListView(
                  padding: const EdgeInsets.fromLTRB(
                    BeanSpace.page,
                    8,
                    BeanSpace.page,
                    120,
                  ),
                  children: [
                    BeanLargeTitle(
                      title: '最近自动记账',
                      subtitle: '今天 $_todayCount 笔 · 点进详情可修改或删除',
                    ),
                    const SizedBox(height: 4),
                    BeanCard(
                      padding: EdgeInsets.zero,
                      child: Column(
                        children: [
                          for (var i = 0; i < _rows.length; i++) ...[
                            if (i > 0) _divider(palette),
                            _EntryRow(
                              row: _rows[i],
                              onTap: () => _open(_rows[i]),
                              onAssign: _rows[i].transaction.needsReview == true
                                  ? () => _assignAccount(_rows[i])
                                  : null,
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
    );
  }

  Widget _divider(BeanPalette palette) => Divider(
        height: BeanSpace.hairline,
        thickness: BeanSpace.hairline,
        indent: 60,
        color: palette.border,
      );
}

class _EntryRow extends StatelessWidget {
  const _EntryRow({
    required this.row,
    required this.onTap,
    this.onAssign,
  });

  final TransactionRow row;
  final VoidCallback onTap;

  /// 待人工处理时提供的「选账户」动作。
  final VoidCallback? onAssign;

  @override
  Widget build(BuildContext context) {
    final palette = BeanPalette.of(context);
    final category = row.category;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(
          children: [
            CategoryAvatar(
              name: category?.name ?? '未分类',
              colorValue: category?.color ?? 0,
              iconKey: category?.icon ?? 'more_horiz',
              size: 36,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    row.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 15, height: 1.25),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    [
                      formatEntryTime(row.transaction.happenedAt),
                      if (sourceAppName(row.transaction.sourcePackage).isNotEmpty)
                        '来自 ${sourceAppName(row.transaction.sourcePackage)}',
                    ].join(' · '),
                    style: TextStyle(fontSize: 12, color: palette.textSecondary),
                  ),
                  if (onAssign != null) ...[
                    const SizedBox(height: 4),
                    TextButton(
                      key: Key('auto-entry-assign-${row.transaction.id}'),
                      onPressed: onAssign,
                      style: TextButton.styleFrom(
                        padding: EdgeInsets.zero,
                        minimumSize: const Size(0, 28),
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      child: const Text('待处理 · 选账户', style: TextStyle(fontSize: 12)),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 8),
            AmountText(
              row.amountCents / 100,
              isIncome: row.isIncome,
              fontSize: 15,
              showSign: !row.isTransfer,
              color: row.isTransfer ? palette.transfer : null,
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyList extends StatelessWidget {
  const _EmptyList();

  @override
  Widget build(BuildContext context) {
    return const BeanEmptyState(
      icon: Icons.auto_awesome_rounded,
      title: '还没有自动记账',
      subtitle: '开启自动记账后，支付完成会自动记到这里',
    );
  }
}
/// 待处理那笔的账户选择器。
class _AccountPicker extends StatelessWidget {
  const _AccountPicker({required this.accounts});

  final List<AccountBalance> accounts;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Text('这笔用哪个账户？', style: TextStyle(fontSize: 15)),
          ),
          for (final balance in accounts)
            ListTile(
              key: Key('auto-entry-account-${balance.account.id}'),
              leading: const Icon(Icons.account_balance_wallet_outlined, size: 20),
              title: Text(balance.account.name),
              onTap: () => Navigator.of(context).pop(balance.account),
            ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}