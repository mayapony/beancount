import '../../data/db/enums.dart';

/// 解析出来的一行（还没和本地数据对照）。
class ParsedRow {
  const ParsedRow({
    required this.lineNumber,
    required this.type,
    required this.categoryName,
    required this.amountCents,
    required this.happenedAt,
    required this.note,
    this.subcategoryName = '',
    this.currency = 'CNY',
    this.accountName = '',
    this.tags = const <String>[],
    this.attachments = const <String>[],
  });

  /// 文件里的行号（表头是第 1 行），报告里用它定位问题。
  final int lineNumber;
  final EntryType type;
  final String categoryName;
  final int amountCents;
  final DateTime happenedAt;
  final String note;
  final String subcategoryName;
  final String currency;
  final String accountName;
  final List<String> tags;
  final List<String> attachments;
}

/// 被跳过的行：原因要能直接展示给用户。
class SkippedRow {
  const SkippedRow({
    required this.lineNumber,
    required this.reason,
    this.summary = '',
  });

  final int lineNumber;
  final String reason;
  final String summary;
}

/// 解析结果。`fatal` 非空时（比如缺列）不该继续。
class ParseResult {
  const ParseResult({
    required this.rows,
    required this.skipped,
    this.fatal,
    this.totalRows = 0,
  });

  final List<ParsedRow> rows;
  final List<SkippedRow> skipped;

  /// 致命错误：缺必需列、不是 BeeCount 导出等。
  final String? fatal;

  /// 数据行总数（含被跳过的）。
  final int totalRows;

  bool get ok => fatal == null;
}

/// 从附件包取出来的图片：文件名 → 原始字节。
typedef AttachmentBytes = Map<String, List<int>>;

/// 一份导入源：CSV 文本 + 可选的图片字节。
class ImportSource {
  const ImportSource({
    required this.csvBytes,
    this.attachments = const <String, List<int>>{},
    this.sourceName = '',
  });

  final List<int> csvBytes;
  final AttachmentBytes attachments;
  final String sourceName;
}
