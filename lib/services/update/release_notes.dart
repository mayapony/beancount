import 'dart:convert';

/// 从 GitHub Release 正文里提取用户可见的变更。
class ReleaseNotes {
  const ReleaseNotes({
    required this.items,
    required this.total,
  });

  /// 实际展示的条目（已按 [limit] 截断）。
  final List<String> items;

  /// 过滤后的总条数。
  final int total;

  bool get truncated => total > items.length;

  bool get isEmpty => items.isEmpty;
}

final _bullet = RegExp(r'^[-*]\s+');
final _userVisible = RegExp(r'^(feat|fix|perf)(\([^)]*\))?!?:');
final _markdownLink = RegExp(r'\[([^\]]+)\]\([^)]*\)');

/// 取 `## 变更` 段，只保留 feat/fix/perf 条目；没有该段时扫描全文。
///
/// 说明为空、全是 docs/test/chore，或没有可读 bullet 时返回空列表。
ReleaseNotes parseReleaseNotes(String body, {int limit = 6}) {
  final lines = const LineSplitter().convert(body);
  var start = 0;
  var end = lines.length;

  for (var i = 0; i < lines.length; i++) {
    if (lines[i].trimLeft().startsWith('## 变更')) {
      start = i + 1;
      end = lines.length;
      for (var j = start; j < lines.length; j++) {
        if (lines[j].trimLeft().startsWith('## ')) {
          end = j;
          break;
        }
      }
      break;
    }
  }

  final all = <String>[];
  for (var i = start; i < end; i++) {
    final line = lines[i].trim();
    final match = _bullet.firstMatch(line);
    if (match == null) continue;
    var item = line.substring(match.end).trim();
    if (item.isEmpty) continue;
    item = item
        .replaceAllMapped(_markdownLink, (m) => m.group(1) ?? '')
        .replaceAll('`', '')
        .trim();
    if (!_userVisible.hasMatch(item)) continue;
    all.add(item);
  }

  final visible = limit <= 0 ? <String>[] : all.take(limit).toList();
  return ReleaseNotes(
    items: visible,
    total: all.length,
  );
}
