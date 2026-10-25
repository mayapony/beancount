library;

import 'capture_candidate.dart';
import 'capture_rule.dart';
import 'capture_tree.dart';

/// 一次规则套用的结果：金额 + 方向。
class CaptureExtraction {
  const CaptureExtraction({required this.amountCents, required this.direction});

  final int amountCents;
  final CaptureDirection direction;
}

/// 规则执行器：套用 LLM 生成的规则，从控件树或通知文本提取金额与方向。
///
/// 只提供策略原语（regex / maxAmount / adjacentLabel），不含任何业务启发式——
/// 具体怎么抽、抽哪里，由 LLM 生成的规则里的策略与参数决定。
class CaptureRuleExecutor {
  const CaptureRuleExecutor();

  /// 套用规则；提取不出金额（无匹配、被排除词命中）时返回 null。
  CaptureExtraction? apply(
    CaptureRule rule, {
    CaptureNode? tree,
    String? text,
  }) {
    final source = rule.target == RuleTarget.accessibility
        ? (tree?.flattenedText ?? '')
        : (text ?? '');
    if (source.trim().isEmpty) return null;

    if (rule.excludeKeywords.any((keyword) => source.contains(keyword))) {
      return null;
    }

    final amount = _extract(rule, source, tree);
    if (amount == null || amount <= 0) return null;
    return CaptureExtraction(amountCents: amount, direction: rule.direction);
  }

  int? _extract(CaptureRule rule, String source, CaptureNode? tree) {
    switch (rule.amountStrategy) {
      case AmountStrategy.regex:
        return _regexAmount(rule.amountPattern, source);
      case AmountStrategy.maxAmount:
        return _maxAmount(source);
      case AmountStrategy.adjacentLabel:
        return _adjacentAmount(rule.adjacentLabel, tree);
    }
  }
}

final _currencyAmountRe = RegExp(
  r'(?:[¥￥]\s*)?(\d{1,3}(?:,\d{3})+|\d+)(?:\.(\d{1,2}))?(?:\s*[元¥￥])?',
);

int? _regexAmount(String? pattern, String source) {
  if (pattern == null || pattern.isEmpty) return null;
  final re = RegExp(pattern);
  final match = re.firstMatch(source);
  if (match == null) return null;
  // 契约：第一捕获组是金额数字串（含可选小数与千分位，不含货币符号）。
  final group = match.groupCount >= 1 ? match.group(1) : match.group(0);
  if (group == null) return null;
  return _parseAmountString(group);
}

int? _maxAmount(String source) {
  final amounts = _findCurrencyAmounts(source);
  if (amounts.isEmpty) return null;
  return amounts.reduce((a, b) => a > b ? a : b);
}

int? _adjacentAmount(String? label, CaptureNode? tree) {
  if (label == null || label.isEmpty || tree == null) return null;
  final lines = tree.flattenedText.split('\n');
  for (var i = 0; i < lines.length; i++) {
    if (!lines[i].contains(label)) continue;
    for (var j = i - 1; j <= i + 1; j++) {
      if (j < 0 || j >= lines.length) continue;
      final amounts = _findCurrencyAmounts(lines[j]);
      if (amounts.isNotEmpty) {
        return amounts.reduce((a, b) => a > b ? a : b);
      }
    }
  }
  return null;
}

/// 找文本里所有「货币形态」的金额；裸整数（无货币符号、无小数）当噪声跳过。
List<int> _findCurrencyAmounts(String source) {
  final amounts = <int>[];
  for (final match in _currencyAmountRe.allMatches(source)) {
    final full = match.group(0)!;
    final intPart = match.group(1)!.replaceAll(',', '');
    final decPart = match.group(2);
    final hasCurrency =
        full.contains('¥') || full.contains('￥') || full.contains('元');
    if (!hasCurrency && decPart == null) continue;
    amounts.add(
      int.parse(intPart) * 100 +
          (decPart == null ? 0 : int.parse(decPart.padRight(2, '0'))),
    );
  }
  return amounts;
}

/// 把「12」「12.50」「1,234.50」这类金额字符串解析成（分）。
int? _parseAmountString(String raw) {
  final cleaned = raw.replaceAll(',', '').trim();
  if (cleaned.isEmpty) return null;
  final parts = cleaned.split('.');
  if (parts.length > 2) return null;
  final intPart = int.tryParse(parts[0]);
  if (intPart == null) return null;
  var cents = intPart * 100;
  if (parts.length == 2) {
    final dec = parts[1];
    if (dec.length > 2) return null;
    cents += int.tryParse(dec.padRight(2, '0')) ?? 0;
  }
  return cents;
}
