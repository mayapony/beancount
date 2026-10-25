library;

import 'capture_candidate.dart';

/// 从捕获文本里解析金额的工具。
///
/// 无障碍 / 通知拿到的都是**文本**（不是图），不经过视觉模型，本地用正则直接
/// 取金额——这正是 design 里的「通用金额提取器」，规则 DSL 只处理它覆盖不了的
/// 长尾界面。

/// 优先当「合计行」的关键词。
const _summaryKeywords = [
  '合计',
  '实付',
  '应付',
  '实付款',
  '支付金额',
  '交易金额',
  'total',
];

final _amountRe = RegExp(
  r'(?:[¥￥]\s*)?(\d{1,3}(?:,\d{3})+|\d+)(?:\.(\d{1,2}))?(?:\s*[元¥￥])?',
);

/// 解析金额（分）；没有可用的金额时返回 null。
///
/// 优先级：含「合计 / 实付 / 应付 / total」等关键词的行里的金额优先（取行内最大），
/// 没有这类行时取全文最大金额。裸整数（无 ¥/￥/元、无小数）被当作订单号 / 日期
/// 之类的噪声，不参与。
int? parseCaptureAmount(String text) {
  if (text.trim().isEmpty) return null;

  final summaryLines = <int>[];
  for (final line in text.split('\n')) {
    if (_isSummaryLine(line)) {
      final amount = _largestInLine(line);
      if (amount != null) summaryLines.add(amount);
    }
  }
  if (summaryLines.isNotEmpty) {
    summaryLines.sort();
    return summaryLines.last;
  }

  int? best;
  for (final line in text.split('\n')) {
    final amount = _largestInLine(line);
    if (amount != null && (best == null || amount > best)) best = amount;
  }
  return best;
}

bool _isSummaryLine(String line) =>
    _summaryKeywords.any((keyword) => line.contains(keyword));

int? _largestInLine(String line) {
  int? best;
  for (final match in _amountRe.allMatches(line)) {
    final cents = _centsFromMatch(match);
    if (cents != null && (best == null || cents > best)) best = cents;
  }
  return best;
}

int? _centsFromMatch(RegExpMatch match) {
  final full = match.group(0)!;
  final intPart = match.group(1)!.replaceAll(',', '');
  final decPart = match.group(2);
  final hasCurrency =
      full.contains('¥') || full.contains('￥') || full.contains('元');
  if (!hasCurrency && decPart == null) return null; // 裸整数，当噪声
  final cents = int.parse(intPart) * 100 +
      (decPart == null ? 0 : int.parse(decPart.padRight(2, '0')));
  return cents;
}

/// 方向判定关键词（退款优先于收款，收款优先于默认的付款）。
const _refundKeywords = ['退款', '退回', '原路退回', '冲正', '撤销'];
const _incomeKeywords = ['收款', '到账', '转入', '收入', '入账'];

/// 排除词：这些词通常意味着「余额 / 优惠 / 额度」等非支付金额。
const _exclusionKeywords = ['余额', '优惠', '立减', '抵扣', '积分', '额度', '待还'];

/// 支付类词：含这些词的文本即便带排除词，仍是一笔支付（如「支付 ¥12.50 立减 ¥2」）。
const _paymentKeywords = [
  '支付',
  '付款',
  '消费',
  '扣款',
  '支出',
  '转账',
  '交易',
  '成功',
];

/// 判定收支方向：退款 → 收款 → 默认付款。
CaptureDirection parseCaptureDirection(String text) {
  if (_containsAny(text, _refundKeywords)) return CaptureDirection.refund;
  if (_containsAny(text, _incomeKeywords)) return CaptureDirection.income;
  return CaptureDirection.expense;
}

/// 是否应排除这则捕获（余额 / 优惠 / 立减等非支付金额）。
///
/// 含排除词且不含支付类词的文本视为余额 / 优惠展示，不当作一笔支付；
/// 同时含支付类词的（「支付 ¥12.50 立减 ¥2」）仍保留。
bool isCaptureExcluded(String text) {
  if (!_containsAny(text, _exclusionKeywords)) return false;
  return !_containsAny(text, _paymentKeywords);
}

bool _containsAny(String text, List<String> keywords) =>
    keywords.any((keyword) => text.contains(keyword));
