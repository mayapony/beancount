/// 从 OCR 文本里读出一笔账的线索。
///
/// 只依赖"数字 + 关键字"，不要求字完全认对——真实 OCR 会把「牛肉面」认成「牛内面」，
/// 但金额与「合计」通常稳。
library;

/// 识别置信度。
enum ReceiptConfidence { none, categoryOnly, amount }

/// 解析结果：可能只有部分字段。
class ReceiptGuess {
  const ReceiptGuess({
    this.amountCents,
    this.categoryName,
    this.note,
    this.happenedAt,
    this.rawText = '',
    this.confidence = ReceiptConfidence.none,
  });

  final int? amountCents;
  final String? categoryName;
  final String? note;
  final DateTime? happenedAt;
  final String rawText;
  final ReceiptConfidence confidence;

  bool get hasAmount => amountCents != null && amountCents! > 0;
  bool get isEmpty => !hasAmount && categoryName == null && (note ?? '').isEmpty;

  static const empty = ReceiptGuess();
}

/// 金额正则：`¥38.50`、`￥ 38.50`、`38.50元`、`1,234.50`。
final _amountPattern = RegExp(
  // \d+ 必须排在前面：否则 "2026" 会被切成 "202"+"6"（当初就是这么错的）
  r'(?:[¥￥]\s*)?(\d+(?:,\d{3})*)(?:\.(\d{1,2}))?\s*(?:元|¥|￥)?',
);

/// 含这些词的行优先当"合计行"。
const _totalKeywords = ['合计', '总计', '实付', '应付', '小计', '总额', 'total'];

/// 商家关键字 → 本地分类名。顺序有意义：更具体的放前面。
const _categoryRules = <String, List<String>>{
  '餐饮': [
    '餐厅', '饭馆', '饭店', '面馆', '小吃', '烧烤', '火锅', '食堂', '咖啡',
    '奶茶', '茶饮', '快餐', '牛肉面', '米线', '饺子', '面', '餐', '食',
  ],
  '交通': ['打车', '滴滴', '出租车', '地铁', '公交', '高铁', '加油', '停车', '机票'],
  '购物': ['超市', '便利店', '商场', '百货', '超市发', '药妆', '网购'],
  '医疗': ['药房', '药店', '医院', '诊所', '体检'],
  '娱乐': ['电影', '影城', 'ktv', '游戏', '演出'],
  '旅行': ['酒店', '民宿', '旅行', '景区', '门票'],
};

/// 解析 OCR 文本。找不到金额时 `confidence` 会降级，但其它字段仍尽量给。
ReceiptGuess parseReceiptText(String text, {DateTime? now}) {
  final raw = text.trim();
  if (raw.isEmpty) return ReceiptGuess.empty;

  final reference = now ?? DateTime.now();
  final lines = raw
      .split(RegExp(r'[\r\n]+'))
      .map((line) => line.trim())
      .where((line) => line.isNotEmpty)
      .toList();

  final amountCents = _pickAmount(lines);
  final category = _pickCategory(raw);
  final note = _pickNote(lines);
  final happenedAt = _pickDate(raw, reference);

  final confidence = amountCents != null
      ? ReceiptConfidence.amount
      : (category != null || (note ?? '').isNotEmpty
          ? ReceiptConfidence.categoryOnly
          : ReceiptConfidence.none);

  return ReceiptGuess(
    amountCents: amountCents,
    categoryName: category,
    note: note,
    happenedAt: happenedAt,
    rawText: raw,
    confidence: confidence,
  );
}

/// 合计行优先；没有合计行时取全文最大金额。
int? _pickAmount(List<String> lines) {
  int? fromTotal;
  final all = <int>[];

  for (final line in lines) {
    final lower = line.toLowerCase();
    final isTotal = _totalKeywords.any(lower.contains);
    final cents = _amountsIn(line);
    if (cents.isEmpty) continue;
    all.addAll(cents);
    if (isTotal) {
      final largest = cents.reduce((a, b) => a > b ? a : b);
      if (fromTotal == null || largest > fromTotal) fromTotal = largest;
    }
  }

  if (fromTotal != null) return fromTotal;
  if (all.isEmpty) return null;
  return all.reduce((a, b) => a > b ? a : b);
}

List<int> _amountsIn(String line) {
  final out = <int>[];
  for (final match in _amountPattern.allMatches(line)) {
    final intPart = match.group(1);
    if (intPart == null) continue;
    final digits = intPart.replaceAll(',', '');
    final yuan = int.tryParse(digits);
    if (yuan == null) continue;
    final fraction = (match.group(2) ?? '').padRight(2, '0');
    final cents = yuan * 100 + int.parse(fraction);
    // 过滤掉明显不是金额的数字：年份、日期片段、电话、订单号
    if (cents == 0) continue;
    final hasDecimal = match.group(2) != null;
    if (digits.length == 4 && !hasDecimal) continue; // 2026
    if (digits.length >= 6 && !hasDecimal) continue; // 订单号/电话
    if (digits.length == 4 && !hasDecimal) continue;
    if (cents > 100000000) continue; // 单笔超过 100 万，多半是号码
    out.add(cents);
  }
  return out;
}

String? _pickCategory(String text) {
  final haystack = text.toLowerCase();
  for (final entry in _categoryRules.entries) {
    for (final keyword in entry.value) {
      if (haystack.contains(keyword.toLowerCase())) return entry.key;
    }
  }
  return null;
}

/// 备注取第一段"像店名"的文字：去掉小票类尾巴与纯数字行。
String? _pickNote(List<String> lines) {
  const noise = ['消费小票', '购物小票', '小票', '收据', '发票', '欢迎光临', '谢谢惠顾'];
  for (final line in lines) {
    if (_amountPattern.hasMatch(line)) continue;
    var candidate = line;
    for (final word in noise) {
      candidate = candidate.replaceAll(word, '');
    }
    candidate = candidate.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (candidate.length < 2) continue;
    if (RegExp(r'^[\d\s:：.\-/年月日]+$').hasMatch(candidate)) continue;
    return candidate;
  }
  return null;
}

DateTime? _pickDate(String text, DateTime now) {
  final patterns = <RegExp>[
    RegExp(r'(\d{4})[-/年](\d{1,2})[-/月](\d{1,2})'),
    RegExp(r'(\d{4})(\d{2})(\d{2})'),
  ];
  for (final pattern in patterns) {
    final m = pattern.firstMatch(text);
    if (m == null) continue;
    final year = int.parse(m.group(1)!);
    final month = int.parse(m.group(2)!);
    final day = int.parse(m.group(3)!);
    if (month < 1 || month > 12 || day < 1 || day > 31) continue;
    if (year < 2000 || year > now.year + 1) continue;
    return DateTime(year, month, day, now.hour, now.minute);
  }
  // 只有月-日：补当年
  final short = RegExp(r'(?<!\d)(\d{1,2})[-/月](\d{1,2})(?!\d)').firstMatch(text);
  if (short != null) {
    final month = int.parse(short.group(1)!);
    final day = int.parse(short.group(2)!);
    if (month >= 1 && month <= 12 && day >= 1 && day <= 31) {
      return DateTime(now.year, month, day, now.hour, now.minute);
    }
  }
  return null;
}
