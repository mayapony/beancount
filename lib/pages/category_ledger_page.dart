import 'package:flutter/material.dart';

import '../data/db/app_database.dart';
import '../data/repositories/attachment_repository.dart';
import '../data/repositories/transaction_repository.dart';
import '../theme/tokens.dart';
import '../utils/money.dart';
import '../widgets/common.dart';
import '../widgets/ledger_day_list.dart';
import 'transaction_detail_page.dart';

/// 分类下钻：某个分类（含二级分类）在一段期间内的逐笔账目。
class CategoryLedgerPage extends StatefulWidget {
  const CategoryLedgerPage({
    super.key,
    required this.category,
    required this.repository,
    this.attachments,
    this.categories = const <Category>[],
    this.from,
    this.to,
    this.rangeLabel = '',
    this.shareOfPeriod,
  });

  final Category category;
  final TransactionRepository repository;
  final AttachmentRepository? attachments;

  /// 打开详情/编辑时要用的分类与账户。
  final List<Category> categories;

  /// 期间（左闭右开）；都为空表示全部时间。
  final DateTime? from;
  final DateTime? to;

  /// 期间的可读名字（「2026年10月」/「全部时间」）。
  final String rangeLabel;

  /// 占该期间支出的比例（0–1），由洞察页算好传进来；为空时不显示。
  final double? shareOfPeriod;

  @override
  State<CategoryLedgerPage> createState() => _CategoryLedgerPageState();
}

class _CategoryLedgerPageState extends State<CategoryLedgerPage> {
  CategoryLedger? _ledger;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final ledger = await widget.repository.categoryLedger(
      widget.category.id,
      from: widget.from,
      to: widget.to,
    );
    if (!mounted) return;
    setState(() => _ledger = ledger);
  }

  Future<void> _open(TransactionRow row) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => TransactionDetailPage(
          row: row,
          repository: widget.repository,
          attachments: widget.attachments,
          categories: widget.categories,
        ),
      ),
    );
    if (mounted) await _load();
  }

  @override
  Widget build(BuildContext context) {
    final palette = BeanPalette.of(context);
    final ledger = _ledger;

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
        title: Text(
          widget.category.name,
          style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
        ),
        centerTitle: true,
      ),
      body: ledger == null
          ? const SizedBox.shrink()
          : ledger.isEmpty
              ? const SafeArea(
                  bottom: false,
                  child: BeanEmptyState(
                    title: '这段时间没有这一类支出',
                    subtitle: '换个时间范围，或者回到明细里看看',
                  ),
                )
              : ListView(
                  padding: const EdgeInsets.only(bottom: 40),
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(
                        BeanSpace.page,
                        4,
                        BeanSpace.page,
                        12,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '¥${formatMoney(ledger.totalCents / 100)}',
                            style: const TextStyle(
                              fontSize: 34,
                              height: 1.1,
                              fontWeight: FontWeight.w700,
                              fontFeatures: [FontFeature.tabularFigures()],
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            [
                              if (widget.rangeLabel.isNotEmpty) widget.rangeLabel,
                              '${ledger.count} 笔',
                              if (widget.shareOfPeriod != null)
                                '占 ${(widget.shareOfPeriod! * 100).round()}%',
                            ].join(' · '),
                            style: TextStyle(
                              fontSize: 13,
                              color: palette.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (ledger.count >= 1000)
                      Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: BeanSpace.page,
                        ),
                        child: Text(
                          '只显示最近 1000 笔',
                          style: TextStyle(
                            fontSize: 12,
                            color: palette.textSecondary,
                          ),
                        ),
                      ),
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: BeanSpace.page,
                      ),
                      child: LedgerDayList(
                        groups: ledger.groups,
                        attachments: widget.attachments,
                        onOpen: _open,
                      ),
                    ),
                  ],
                ),
    );
  }
}
