import 'package:flutter/material.dart';

import '../services/update/release_notes.dart';
import '../theme/tokens.dart';

/// 更新说明：默认只展示前几条，可展开全部。
class ReleaseNotesView extends StatefulWidget {
  const ReleaseNotesView({super.key, required this.notes, this.limit = 6});

  final String notes;
  final int limit;

  @override
  State<ReleaseNotesView> createState() => _ReleaseNotesViewState();
}

class _ReleaseNotesViewState extends State<ReleaseNotesView> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final palette = BeanPalette.of(context);
    final parsed = parseReleaseNotes(
      widget.notes,
      limit: _expanded ? 1000 : widget.limit,
    );

    if (parsed.isEmpty) {
      return Text(
        '本次发布没有提供更新说明',
        style: TextStyle(fontSize: 13, color: palette.textSecondary),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final item in parsed.items)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Container(
                    width: 5,
                    height: 5,
                    decoration: BoxDecoration(
                      color: BeanColors.goldDeep,
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    item,
                    style: const TextStyle(fontSize: 14, height: 1.45),
                  ),
                ),
              ],
            ),
          ),
        if (parsed.truncated || _expanded)
          TextButton(
            key: const ValueKey('update-notes-toggle'),
            onPressed: () => setState(() => _expanded = !_expanded),
            style: TextButton.styleFrom(
              padding: EdgeInsets.zero,
              minimumSize: const Size(0, 32),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            child: Text(
              _expanded ? '收起' : '展开全部（${parsed.total} 条）',
              style: const TextStyle(fontSize: 13),
            ),
          ),
      ],
    );
  }
}
