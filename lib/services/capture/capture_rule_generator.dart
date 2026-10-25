library;

import 'capture_candidate.dart';
import 'capture_rule.dart';
import 'capture_tree.dart';

/// 规则生成请求：脱敏树快照 + 真值金额 + 元数据。
class CaptureRuleGenerationRequest {
  const CaptureRuleGenerationRequest({
    required this.packageName,
    required this.target,
    required this.direction,
    required this.desensitizedTree,
    required this.amountCents,
    this.surfaceFingerprint,
  });

  final String packageName;
  final RuleTarget target;
  final CaptureDirection direction;

  /// 脱敏后的树快照（结构 + 标签 + 金额形态，无数字、无整屏截图）。
  final String desensitizedTree;

  /// 真值金额（分）：来自截图视觉模型的当次入账，供 LLM 对齐「哪个节点是金额」。
  final int amountCents;

  final String? surfaceFingerprint;
}

/// 规则生成器：把（脱敏树快照 + 真值金额）变成一条 DSL 规则。
abstract class CaptureRuleGenerator {
  Future<CaptureRule> generate(CaptureRuleGenerationRequest request);

  /// 释放底层资源（如 HTTP 客户端）；默认无操作。
  void close() {}
}

/// 规则生成编排：未配置云端模型时直接跳过——不调用生成器、不上传任何内容。
class RuleGenerationService {
  RuleGenerationService({
    required this.generator,
    required this.isConfigured,
  });

  final CaptureRuleGenerator generator;
  final Future<bool> Function() isConfigured;

  Future<CaptureRule?> generate(CaptureRuleGenerationRequest request) async {
    if (!await isConfigured()) return null;
    return generator.generate(request);
  }
}

/// 脱敏：把树 dump 成「缩进 + className|文本」，所有数字掩成 `#`。
///
/// 保留结构、标签与金额形态（`¥##.##`），掩掉金额数字与订单号等动态数字；
/// 不含整屏截图。真值金额由请求单独携带，不出现在这里。
String desensitizeTree(CaptureNode root) {
  final buf = StringBuffer();
  _dump(root, buf, 0);
  return buf.toString().trim();
}

void _dump(CaptureNode node, StringBuffer buf, int depth) {
  final indent = '  ' * depth;
  final text = node.text?.trim();
  if (text != null && text.isNotEmpty) {
    buf.writeln('$indent${node.className ?? ''}|${_maskDigits(text)}');
  } else if (node.className != null && node.className!.isNotEmpty) {
    buf.writeln('$indent${node.className}');
  }
  for (final child in node.children) {
    _dump(child, buf, depth + 1);
  }
}

String _maskDigits(String text) => text.replaceAll(RegExp(r'\d'), '#');
