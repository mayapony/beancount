/// 一笔账的识别结果：模型直接给出结构化字段，本地不再做文字规则解析。
library;

/// 识别置信度。
enum ReceiptConfidence { none, categoryOnly, amount }

/// 解析结果：可能只有部分字段。
class ReceiptGuess {
  const ReceiptGuess({
    this.amountCents,
    this.categoryName,
    this.tagNames = const [],
    this.accountName,
    this.note,
    this.happenedAt,
    this.confidence = ReceiptConfidence.none,
  });

  final int? amountCents;
  final String? categoryName;

  /// 标签候选（固定词表，最多 2 个）。
  final List<String> tagNames;

  /// 支付渠道线索（微信/支付宝/云闪付/银行卡），已归一化为规范名，未与本地账户核对。
  final String? accountName;
  final String? note;
  final DateTime? happenedAt;
  final ReceiptConfidence confidence;

  bool get hasAmount => amountCents != null && amountCents! > 0;
  bool get isEmpty => !hasAmount && categoryName == null && (note ?? '').isEmpty;

  static const empty = ReceiptGuess();

  ReceiptGuess copyWith({
    int? amountCents,
    String? categoryName,
    List<String>? tagNames,
    String? accountName,
    String? note,
    DateTime? happenedAt,
    ReceiptConfidence? confidence,
  }) {
    return ReceiptGuess(
      amountCents: amountCents ?? this.amountCents,
      categoryName: categoryName ?? this.categoryName,
      tagNames: tagNames ?? this.tagNames,
      accountName: accountName ?? this.accountName,
      note: note ?? this.note,
      happenedAt: happenedAt ?? this.happenedAt,
      confidence: confidence ?? this.confidence,
    );
  }
}
