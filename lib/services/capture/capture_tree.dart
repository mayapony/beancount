library;

/// 无障碍控件树的节点（原生侧读树后转发给 Dart 的最小表示）。
class CaptureNode {
  const CaptureNode({
    this.text,
    this.className,
    this.viewId,
    this.bounds,
    this.children = const [],
  });

  final String? text;
  final String? className;
  final String? viewId;

  /// `left,top,right,bottom` 字符串。
  final String? bounds;

  final List<CaptureNode> children;

  /// 平铺文本：先序拼接所有节点文本，供 regex 策略与排除词使用。
  String get flattenedText {
    final buf = StringBuffer();
    _appendText(buf);
    return buf.toString().trim();
  }

  void _appendText(StringBuffer buf) {
    final t = text?.trim();
    if (t != null && t.isNotEmpty) buf.writeln(t);
    for (final child in children) {
      child._appendText(buf);
    }
  }

  int get totalNodeCount =>
      1 + children.fold(0, (sum, child) => sum + child.totalNodeCount);
}

/// 计算 surface 结构指纹：节点数分桶 + 关键标签集合 + bounds 布局的稳定散列。
///
/// 「关键标签」排除含数字 / 货币符号的动态文本（金额、订单号），只保留稳定标签，
/// 让同一页面在不同支付实例下指纹保持一致。
String surfaceFingerprintOf(CaptureNode root) {
  final countBucket = _countBucket(root.totalNodeCount);
  final labels = <String>{};
  final layout = <String>[];
  _collect(root, labels, layout);
  final source = [
    countBucket,
    (labels.toList()..sort()).join(','),
    layout.join(','),
  ].join('|');
  return _stableHash(source);
}

final _amountLikeRe = RegExp(r'[¥￥0-9]');

void _collect(CaptureNode node, Set<String> labels, List<String> layout) {
  final t = node.text?.trim();
  if (t != null && t.isNotEmpty) {
    if (!_amountLikeRe.hasMatch(t)) labels.add(t);
    final b = node.bounds;
    if (b != null) layout.add(_bucketBounds(b));
  }
  for (final child in node.children) {
    _collect(child, labels, layout);
  }
}

String _countBucket(int count) {
  if (count <= 10) return '0-10';
  if (count <= 50) return '11-50';
  if (count <= 200) return '51-200';
  return '201+';
}

String _bucketBounds(String bounds) {
  final parts = bounds.split(',');
  if (parts.length != 4) return bounds;
  final coords = <int>[];
  for (final p in parts) {
    final v = int.tryParse(p.trim());
    if (v == null) return bounds;
    coords.add(v);
  }
  return coords.map((c) => (c ~/ 100) * 100).join(',');
}

String _stableHash(String source) {
  var hash = 0x811c9dc5;
  for (final code in source.codeUnits) {
    hash ^= code;
    hash = (hash * 0x01000193) & 0xFFFFFFFF;
  }
  return hash.toRadixString(16).padLeft(8, '0');
}
