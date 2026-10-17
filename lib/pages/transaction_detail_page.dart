import 'dart:io';

import 'package:flutter/material.dart';

import '../data/repositories/attachment_repository.dart';
import '../data/repositories/transaction_repository.dart';
import '../theme/tokens.dart';
import '../utils/dates.dart';
import '../utils/money.dart';
import '../widgets/common.dart';
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
  });

  final TransactionRow row;
  final TransactionRepository repository;
  final AttachmentRepository? attachments;

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
        builder: (_) => AttachmentViewerPage(files: _images, initialIndex: index),
      ),
    );
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
                if (account != null)
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
    final category = row.category;
    return Column(
      children: [
        CategoryAvatar(
          name: category.name,
          colorValue: category.color,
          iconKey: category.icon,
          size: 56,
        ),
        const SizedBox(height: 12),
        AmountText(
          row.amountCents / 100,
          isIncome: row.isIncome,
          fontSize: 34,
          fontWeight: FontWeight.w600,
          showSign: true,
        ),
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
