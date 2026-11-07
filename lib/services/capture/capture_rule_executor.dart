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

/// 一次套用的完整过程：要么抽出金额，要么说明为什么没抽出来。
class CaptureAttempt {
  const CaptureAttempt({this.extraction, this.excludedKeyword});

  /// 抽出来的金额；为空表示没抽到。
  final CaptureExtraction? extraction;

  /// 命中排除词时记的是哪个词——排查时不用再猜。
  final String? excludedKeyword;

  bool get matched => extraction != null;
}

/// 规则执行器：套用 LLM 生成的规则，从控件树或通知文本提取金额与方向。
///
/// 只提供策略原语（regex / adjacentLabel），不含任何业务启发式——
/// 具体怎么抽、抽哪里，由 LLM 生成的规则里的策略与参数决定。
///
/// 排除词只在**金额所在行及其相邻行**内匹配。以前是拿整页文本判断，页面底部
/// 随便一句「领积分」「券」就会把整笔判成「不是支付」，规则回放验证随之永远
/// 失败、停在待定。
class CaptureRuleExecutor {
  const CaptureRuleExecutor();

  /// 套用规则；提取不出金额（无匹配、被排除词命中）时返回 null。
  CaptureExtraction? apply(
    CaptureRule rule, {
    CaptureNode? tree,
    String? text,
  }) =>
      attempt(rule, tree: tree, text: text).extraction;

  /// 套用规则并返回过程细节，供运行记录使用。
  CaptureAttempt attempt(
    CaptureRule rule, {
    CaptureNode? tree,
    String? text,
  }) {
    final source = rule.target == RuleTarget.accessibility
        ? (tree?.flattenedText ?? '')
        : (text ?? '');
    if (source.trim().isEmpty) return const CaptureAttempt();

    final amount = _extract(rule, source, tree);
    if (amount == null || amount <= 0) return const CaptureAttempt();

    final keyword = _excludedKeyword(rule, source, amount);
    if (keyword != null) return CaptureAttempt(excludedKeyword: keyword);

    return CaptureAttempt(
      extraction: CaptureExtraction(
        amountCents: amount,
        direction: rule.direction,
      ),
    );
  }

  /// 排除词命中在金额邻域内才算数；定位不到金额行时退回整段（保持旧行为，
  /// 宁可漏记也不误记）。
  String? _excludedKeyword(CaptureRule rule, String source, int amount) {
    if (rule.excludeKeywords.isEmpty) return null;
    final window = _amountWindow(rule, source, amount);
    for (final keyword in rule.excludeKeywords) {
      if (window.contains(keyword)) return keyword;
    }
    return null;
  }

  /// 金额所在行 ±1 行；通知文本只有一段时等价于整段。
  String _amountWindow(CaptureRule rule, String source, int amount) {
    final lines = source.split('\n');
    for (var i = 0; i < lines.length; i++) {
      if (!_lineYieldsAmount(rule, lines[i], amount)) continue;
      final from = i > 0 ? i - 1 : 0;
      final to = i + 1 < lines.length ? i + 1 : lines.length - 1;
      return lines.sublist(from, to + 1).join('\n');
    }
    return source;
  }

  bool _lineYieldsAmount(CaptureRule rule, String line, int amount) {
    for (final candidate in _findCurrencyAmounts(line)) {
      if (candidate == amount) return true;
    }
    final pattern = rule.amountPattern;
    if (pattern == null || pattern.isEmpty) return false;
    try {
      final match = RegExp(pattern).firstMatch(line);
      if (match == null) return false;
      final group = match.groupCount >= 1 ? match.group(1) : match.group(0);
      return group != null && _parseAmountString(group) == amount;
    } on FormatException {
      return false;
    }
  }

  /// 同一条 regex 在页面上命中的不同金额集合。用于判断规则是不是「只会抓第一个
  /// 数字」——同一页命中多个不同金额，说明它没锚定到实付。
  Set<int> distinctRegexAmounts(String pattern, String source) {
    final out = <int>{};
    try {
      for (final match in RegExp(pattern).allMatches(source)) {
        final group = match.groupCount >= 1 ? match.group(1) : match.group(0);
        if (group == null) continue;
        final amount = _parseAmountString(group);
        if (amount != null) out.add(amount);
      }
    } on FormatException {
      return out;
    }
    return out;
  }

  int? _extract(CaptureRule rule, String source, CaptureNode? tree) {
    switch (rule.amountStrategy) {
      case AmountStrategy.regex:
        return _regexAmount(rule.amountPattern, source);
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
