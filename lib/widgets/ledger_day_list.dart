import 'dart:io';

import 'package:flutter/material.dart';

import '../data/repositories/attachment_repository.dart';
import '../data/repositories/transaction_repository.dart';
import '../theme/tokens.dart';
import '../utils/dates.dart';
import '../utils/money.dart';
import '../widgets/common.dart';
import '../pages/attachment_viewer_page.dart';

/// 按天分组的交易列表：明细页与搜索页共用同一份排版。
///
/// 抽出来的原因很简单——两处必须长得一模一样，规则只写一次才不会漂移。
class LedgerDayList extends StatelessWidget {
  const LedgerDayList({
    super.key,
    required this.groups,
    this.attachments,
    required this.onOpen,
  });

  final List<DayGroup> groups;

  /// 附件仓储：把库里的文件名还原成缩略图。
  final AttachmentRepository? attachments;

  /// 点某一行（进详情）。
  final ValueChanged<TransactionRow> onOpen;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final group in groups)
          _DaySection(
            group: group,
            attachments: attachments,
            onOpen: onOpen,
          ),
      ],
    );
  }
}

class _DaySection extends StatelessWidget {
  const _DaySection({
    required this.group,
    this.attachments,
    required this.onOpen,
  });

  final DayGroup group;
  final AttachmentRepository? attachments;
  final ValueChanged<TransactionRow> onOpen;

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
                    _EntryRow(
                      row: group.items[i],
                      attachments: attachments,
                      onTap: () => onOpen(group.items[i]),
                    ),
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

class _EntryRow extends StatelessWidget {
  const _EntryRow({required this.row, this.attachments, required this.onTap});

  final TransactionRow row;
  final AttachmentRepository? attachments;

  /// 点整行进详情；缩略图有自己的热区，点了先被它吃掉。
  final VoidCallback onTap;

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
    final subtitle = row.isTransfer
        ? [
            formatClock(row.transaction.happenedAt),
            '${row.account?.name ?? '账户'} → ${row.toAccount?.name ?? '账户'}',
          ].join(' · ')
        : <String>[
            formatClock(row.transaction.happenedAt),
            category?.name ?? '未分类',
            if (row.account != null) row.account!.name,
          ].join(' · ');

    final thumbName = row.thumbnailFileName;
    final thumbFile =
        thumbName == null ? null : attachments?.fileFor(thumbName);

    return InkWell(
      onTap: onTap,
      // 行高 56：iOS 列表的节奏，比原来的 64 更紧凑但留白更多
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 11,
        ),
        child: Row(
          children: [
            if (row.isTransfer)
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: palette.neutral.sand,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.swap_horiz_rounded,
                  size: 20,
                  color: palette.transfer,
                ),
              )
            else
              CategoryAvatar(
                name: category?.name ?? '未分类',
                colorValue: category?.color ?? 0,
                iconKey: category?.icon ?? 'more_horiz',
              ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    row.title,
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
              showSign: !row.isTransfer,
              color: row.isTransfer ? palette.transfer : null,
            ),
          ],
        ),
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
                  errorBuilder: (_, __, ___) => _placeholder(palette),
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
