import 'dart:io';

import 'package:flutter/material.dart';

import '../data/db/app_database.dart';
import '../data/db/enums.dart';
import '../data/repositories/account_repository.dart';
import '../data/repositories/attachment_repository.dart';
import '../data/repositories/transaction_repository.dart';
import '../theme/tokens.dart';
import '../utils/dates.dart';
import '../utils/money.dart';
import '../widgets/common.dart';
import '../widgets/quick_entry_sheet.dart';
import 'attachment_viewer_page.dart';

/// 一笔账的详情：金额、分类/账户/时间/备注、标签与图片。
///
/// 它同时也是「编辑 / 删除」的入口（见后续任务），所以拿的是完整仓储而不是单行数据。
class TransactionDetailPage extends StatefulWidget {
  const TransactionDetailPage({
    super.key,
    required this.row,
    required this.repository,
    this.attachments,
    this.categories = const <Category>[],
    this.accounts = const <AccountBalance>[],
  });

  final TransactionRow row;
  final TransactionRepository repository;
  final AttachmentRepository? attachments;

  /// 编辑面板要用的分类与账户；为空时只读展示（不提供编辑）。
  final List<Category> categories;
  final List<AccountBalance> accounts;

  @override
  State<TransactionDetailPage> createState() => _TransactionDetailPageState();
}

class _TransactionDetailPageState extends State<TransactionDetailPage> {
  // 编辑保存后要换成新的行数据，所以不是 final
  // ignore: prefer_final_fields
  late TransactionRow _row = widget.row;
  List<File> _images = const [];
  List<String> _tags = const [];

  @override
  void initState() {
    super.initState();
    _loadExtras();
  }

  /// 标签与图片不在列表行里，进页面时补一次。
  Future<void> _loadExtras() async {
    final repo = widget.attachments;
    final images = <File>[];
    if (repo != null) {
      final rows = await repo.attachmentsOf(_row.transaction.id);
      for (final attachment in rows) {
        final file = repo.fileFor(attachment.fileName);
        if (file != null && file.existsSync()) images.add(file);
      }
    }
    final tags = await widget.repository.tagsOf(_row.transaction.id);
    if (!mounted) return;
    setState(() {
      _images = images;
      _tags = tags;
    });
  }

  Future<void> _openImages(int index) async {
    if (_images.isEmpty) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) =>
            AttachmentViewerPage(files: _images, initialIndex: index),
      ),
    );
  }

  /// 打开预填面板改这一笔；保存成功后刷新本页与明细（明细靠数据流自动刷新）。
  Future<void> _edit() async {
    final transaction = _row.transaction;
    final draft = QuickEntryDraft(
      amount: transaction.amountCents / 100,
      isIncome: _row.isIncome,
      isTransfer: _row.isTransfer,
      category: _row.category,
      account: _row.account,
      toAccount: _row.toAccount,
      time: transaction.happenedAt,
      note: transaction.note,
      tags: _tags,
    );

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => QuickEntrySheet(
        categories: widget.categories,
        accounts: widget.accounts,
        initialDraft: draft,
        onSubmit: (input) async {
          try {
            await widget.repository.update(
              transaction.id,
              TransactionEdit(
                type: input.isTransfer
                    ? EntryType.transfer
                    : (input.isIncome ? EntryType.income : EntryType.expense),
                amountCents: (input.amount * 100).round(),
                categoryId: input.isTransfer ? null : input.category?.id,
                happenedAt: input.time,
                accountId: input.account?.id,
                toAccountId: input.isTransfer ? input.toAccount?.id : null,
                note: input.note,
                tags: input.tags,
              ),
            );
            return null;
          } on DuplicateTransactionException {
            return '已存在相同时间、金额与备注的记录';
          }
        },
      ),
    );

    if (!mounted) return;
    final fresh = await widget.repository.byId(_row.transaction.id);
    if (fresh == null || !mounted) return;
    setState(() => _row = fresh);
    await _loadExtras();
  }

  /// 删除这一笔：先确认（把金额说清楚，避免删错），删完退回明细。
  Future<void> _delete() async {
    final palette = BeanPalette.of(context);
    final amount = formatMoney(_row.amountCents / 100);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除这笔？'),
        content: Text('${_row.title}  $amount\n删除后无法恢复，关联的图片也会一并清理。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('取消'),
          ),
          TextButton(
            style: TextButton.styleFrom(foregroundColor: palette.alert),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    await widget.repository.delete(_row.transaction.id);
    if (!mounted) return;
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final palette = BeanPalette.of(context);
    final category = _row.category;
    final account = _row.account;
    final note = _row.transaction.note.trim();

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
          _row.isIncome ? '收入' : '支出',
          style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
        ),
        centerTitle: true,
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(
          BeanSpace.page,
          8,
          BeanSpace.page,
          120,
        ),
        children: [
          _AmountHeader(row: _row),
          const SizedBox(height: BeanSpace.section),
          BeanCard(
            padding: EdgeInsets.zero,
            child: Column(
              children: [
                if (category != null)
                  _DetailRow(
                    label: '分类',
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        CategoryAvatar(
                          name: category.name,
                          colorValue: category.color,
                          iconKey: category.icon,
                          size: 22,
                        ),
                        const SizedBox(width: 8),
                        Text(category.name, style: _valueStyle),
                      ],
                    ),
                  ),
                if (_row.isTransfer) ...[
                  _DetailRow(
                    label: '从',
                    child: Text(
                      _row.account?.name ?? '账户',
                      style: _valueStyle,
                    ),
                  ),
                  _DetailRow(
                    label: '到',
                    child: Text(
                      _row.toAccount?.name ?? '账户',
                      style: _valueStyle,
                    ),
                  ),
                ] else if (account != null)
                  _DetailRow(
                    label: '账户',
                    child: Text(account.name, style: _valueStyle),
                  ),
                _DetailRow(
                  label: '时间',
                  child: Text(
                    formatEntryTime(_row.transaction.happenedAt),
                    style: _valueStyle,
                  ),
                ),
                if (note.isNotEmpty)
                  _DetailRow(
                    label: '备注',
                    child: Text(
                      note,
                      textAlign: TextAlign.right,
                      style: _valueStyle,
                    ),
                  ),
              ],
            ),
          ),
          if (_tags.isNotEmpty) ...[
            const SizedBox(height: BeanSpace.section),
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                '标签',
                style: TextStyle(fontSize: 13, color: palette.textSecondary),
              ),
            ),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final tag in _tags) _TagChip(label: tag),
              ],
            ),
          ],
          if (_images.isNotEmpty) ...[
            const SizedBox(height: BeanSpace.section),
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                '图片 · ${_images.length}',
                style: TextStyle(fontSize: 13, color: palette.textSecondary),
              ),
            ),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (var i = 0; i < _images.length; i++)
                  GestureDetector(
                    onTap: () => _openImages(i),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: Image.file(
                        _images[i],
                        width: 96,
                        height: 96,
                        fit: BoxFit.cover,
                        cacheWidth: 200,
                        errorBuilder: (_, __, ___) => Container(
                          width: 96,
                          height: 96,
                          color: palette.neutral.sand,
                          child: Icon(
                            Icons.broken_image_rounded,
                            size: 20,
                            color: palette.neutral.iconNeutral,
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ],
          if (widget.categories.isNotEmpty) ...[
            const SizedBox(height: BeanSpace.section),
            SizedBox(
              width: double.infinity,
              height: 48,
              child: FilledButton(
                onPressed: _edit,
                child: const Text('编辑'),
              ),
            ),
          ],
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            height: 48,
            child: TextButton(
              onPressed: _delete,
              style: TextButton.styleFrom(foregroundColor: palette.alert),
              child: const Text('删除这笔'),
            ),
          ),
        ],
      ),
    );
  }

  static const TextStyle _valueStyle = TextStyle(fontSize: 15);
}

class _AmountHeader extends StatelessWidget {
  const _AmountHeader({required this.row});

  final TransactionRow row;

  @override
  Widget build(BuildContext context) {
    final palette = BeanPalette.of(context);
    final category = row.category;
    return Column(
      children: [
        if (row.isTransfer)
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: palette.neutral.sand,
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.swap_horiz_rounded,
              size: 28,
              color: palette.transfer,
            ),
          )
        else
          CategoryAvatar(
            name: category?.name ?? '未分类',
            colorValue: category?.color ?? 0,
            iconKey: category?.icon ?? 'more_horiz',
            size: 56,
          ),
        const SizedBox(height: 12),
        AmountText(
          row.amountCents / 100,
          isIncome: row.isIncome,
          fontSize: 34,
          fontWeight: FontWeight.w600,
          showSign: !row.isTransfer,
          color: row.isTransfer ? palette.transfer : null,
        ),
        if (row.isTransfer) ...[
          const SizedBox(height: 4),
          Text(
            '${row.account?.name ?? '账户'} → ${row.toAccount?.name ?? '账户'}',
            style: TextStyle(fontSize: 13, color: palette.textSecondary),
          ),
        ],
      ],
    );
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({required this.label, required this.child});

  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final palette = BeanPalette.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color: palette.border,
            width: BeanSpace.hairline,
          ),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(fontSize: 15, color: palette.textSecondary),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Align(alignment: Alignment.centerRight, child: child),
          ),
        ],
      ),
    );
  }
}

class _TagChip extends StatelessWidget {
  const _TagChip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final palette = BeanPalette.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: palette.neutral.sand,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        '#$label',
        style: TextStyle(fontSize: 13, color: palette.textSecondary),
      ),
    );
  }
}
