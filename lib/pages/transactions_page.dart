import 'dart:io';

import 'package:flutter/material.dart';

import '../data/repositories/attachment_repository.dart';
import '../data/repositories/transaction_repository.dart';
import '../theme/tokens.dart';
import '../utils/dates.dart';
import '../utils/money.dart';
import '../widgets/common.dart';
import 'attachment_viewer_page.dart';

/// 明细页：按天分组的交易列表，数据来自本地库（写入后自动刷新）。
class TransactionsPage extends StatefulWidget {
  const TransactionsPage({
    super.key,
    required this.repository,
    this.attachments,
  });

  final TransactionRepository repository;

  /// 附件仓储：用来把库里的文件名还原成磁盘路径，画 32×32 缩略图。
  final AttachmentRepository? attachments;

  @override
  State<TransactionsPage> createState() => _TransactionsPageState();
}

class _TransactionsPageState extends State<TransactionsPage> {
  late final Stream<List<DayGroup>> _stream = widget.repository.watchDayGroups();

  @override
  void initState() {
    super.initState();
    // 先把附件目录解析好：列表里的缩略图需要同步拿路径
    widget.attachments?.ensureReady();
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<DayGroup>>(
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
        final groups = snapshot.data;
        if (groups == null) {
          // 首帧还没读到库：留白，不闪"空账本"
          return const SizedBox.shrink();
        }
        if (groups.isEmpty) {
          return const SafeArea(
            bottom: false,
            child: BeanEmptyState(
              title: '还没有记账',
              subtitle: '点下方的金豆，记下第一笔',
            ),
          );
        }
        return _Ledger(groups: groups, attachments: widget.attachments);
      },
    );
  }
}

class _Ledger extends StatelessWidget {
  const _Ledger({required this.groups, this.attachments});

  final List<DayGroup> groups;
  final AttachmentRepository? attachments;

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

    final newest = groups.first.date;
    final title = '${newest.month}月';

    return SafeArea(
      bottom: false,
      child: ListView(
        padding: const EdgeInsets.only(bottom: 120),
        children: [
          // 没有「明细」标题：月份就是标题，底部 tab 已经说明这是哪一页
          BeanLargeTitle(
            title: title,
            subtitle: '${newest.year}年 · ${expenseCount + incomeCount} 笔收支',
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
          ...groups.map((group) => _DaySection(
                group: group, attachments: attachments)),
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

class _DaySection extends StatelessWidget {
  const _DaySection({required this.group, this.attachments});

  final DayGroup group;
  final AttachmentRepository? attachments;

  @override
  Widget build(BuildContext context) {
    final palette = BeanPalette.of(context);
    return Padding(
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
                  formatDayHeader(group.date),
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: palette.textSecondary,
                  ),
                ),
                const Spacer(),
                if (group.expenseCents > 0)
                  Text(
                    '支出 ${formatMoney(group.expenseCents / 100)}',
                    style: TextStyle(
                      fontSize: 12,
                      color: palette.textSecondary,
                    ),
                  ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: BeanSpace.page),
            child: BeanCard(
              padding: EdgeInsets.zero,
              child: Column(
                children: [
                  for (var i = 0; i < group.items.length; i++) ...[
                    _EntryRow(row: group.items[i], attachments: attachments),
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
    );
  }
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

class _EntryRow extends StatelessWidget {
  const _EntryRow({required this.row, this.attachments});

  final TransactionRow row;
  final AttachmentRepository? attachments;

  Future<void> _openAttachments(BuildContext context) async {
    final repo = attachments;
    if (repo == null) return;
    final rows = await repo.attachmentsOf(row.transaction.id);
    final files = <File>[
      for (final a in rows)
        if (repo.fileFor(a.fileName)?.existsSync() ?? false)
          repo.fileFor(a.fileName)!,
    ];
    if (!context.mounted) return;
    if (files.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('图片文件已丢失')),
      );
      return;
    }
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => AttachmentViewerPage(files: files),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final palette = BeanPalette.of(context);
    final category = row.category;
    final note = row.transaction.note.trim();
    final subtitle = <String>[
      formatClock(row.transaction.happenedAt),
      category.name,
      if (row.account != null) row.account!.name,
    ].join(' · ');

    final thumbName = row.thumbnailFileName;
    final thumbFile = thumbName == null ? null : attachments?.fileFor(thumbName);

    return Padding(
      // 行高 56：iOS 列表的节奏，比原来的 64 更紧凑但留白更多
      padding: const EdgeInsets.symmetric(
        horizontal: 16,
        vertical: 11,
      ),
      child: Row(
        children: [
          CategoryAvatar(
            name: category.name,
            colorValue: category.color,
            iconKey: category.icon,
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  note.isEmpty ? category.name : note,
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
                  subtitle,
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
          const SizedBox(width: 8),
          // 有图才占位：没图的交易不留空白
          if (thumbName != null) ...[
            _AttachmentThumb(
              file: thumbFile,
              onTap: () => _openAttachments(context),
            ),
            const SizedBox(width: 8),
          ],
          AmountText(
            row.amountCents / 100,
            isIncome: row.isIncome,
            fontSize: 17,
            fontWeight: FontWeight.w500,
          ),
        ],
      ),
    );
  }
}

/// 32×32 圆角缩略图：文件还没解析出来时给一块占位，避免行高跳动。
class _AttachmentThumb extends StatelessWidget {
  const _AttachmentThumb({required this.file, required this.onTap});

  final File? file;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = BeanPalette.of(context);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(6),
        child: SizedBox(
          width: 32,
          height: 32,
          child: file != null && file!.existsSync()
              ? Image.file(
                  file!,
                  fit: BoxFit.cover,
                  cacheWidth: 96,
                  errorBuilder: (_, __, ___) =>
                      _placeholder(palette),
                )
              : _placeholder(palette),
        ),
      ),
    );
  }

  Widget _placeholder(BeanPalette palette) => ColoredBox(
        color: palette.neutral.sand,
        child: Icon(
          Icons.image_rounded,
          size: 16,
          color: palette.neutral.iconNeutral,
        ),
      );
}
