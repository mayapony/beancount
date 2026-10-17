import 'dart:convert';

import 'package:csv/csv.dart';
import 'package:excel/excel.dart';
import 'package:gbk_codec/gbk_codec.dart';

import '../../data/db/enums.dart';
import 'bee_count_csv.dart';
import 'import_models.dart';

/// 账单来源。
enum StatementKind {
  alipay('支付宝账单'),
  wechat('微信支付账单'),
  beecount('BeeCount 导出'),
  unknown('未识别');

  const StatementKind(this.label);

  final String label;
}

/// 识别结果：格式 + 解析器决定的行。
class StatementParse {
  const StatementParse({
    required this.kind,
    required this.result,
    this.fileLabel = '',
  });

  final StatementKind kind;
  final ParseResult result;

  /// 给界面显示的名字（例如支付宝账单里的账户名）。
  final String fileLabel;
}

/// 统一入口：BeeCount CSV、支付宝/微信账单（含 GBK）、Excel（xlsx）。
///
/// 只做"识别 + 解析"，产出与 BeeCount 导入相同的 `ParsedRow`，
/// 去重、分类创建、报告、附件都复用现有管线。
Future<StatementParse> parseImportFile(
  List<int> bytes, {
  String fileName = '',
}) async {
  if (_looksLikeXlsx(bytes)) {
    final matrix = _readXlsx(bytes);
    if (matrix == null) {
      return const StatementParse(
        kind: StatementKind.unknown,
        result: ParseResult(
          rows: [],
          skipped: [],
          fatal: '这个 Excel 文件读不出来（只支持 .xlsx）',
        ),
      );
    }
    return _parseMatrix(matrix, fileName: fileName);
  }

  final text = decodeStatementText(bytes);
  if (text == null) {
    return const StatementParse(
      kind: StatementKind.unknown,
      result: ParseResult(
        rows: [],
        skipped: [],
        fatal: '无法识别文件编码（支持 UTF-8 与 GBK）',
      ),
    );
  }

  final matrix = <List<String>>[
    for (final row in CsvToListConverter(
      shouldParseNumbers: false,
      eol: '\n',
    ).convert(text.replaceAll('\r\n', '\n').replaceAll('\r', '\n')))
      [for (final cell in row) '$cell'],
  ];

  final kind = detectKind(matrix);
  if (kind == StatementKind.beecount) {
    return StatementParse(
      kind: kind,
      result: parseBeeCountCsv(bytes),
    );
  }
  return _parseMatrix(matrix, fileName: fileName);
}

/// UTF-8 优先，失败回退 GBK（支付宝导出就是 GBK）。
String? decodeStatementText(List<int> bytes) {
  try {
    return utf8.decode(bytes);
  } on FormatException {
    try {
      return gbk.decode(bytes);
    } catch (_) {
      return null;
    }
  }
}

bool _looksLikeXlsx(List<int> bytes) =>
    bytes.length > 4 &&
    bytes[0] == 0x50 &&
    bytes[1] == 0x4B &&
    bytes[2] == 0x03 &&
    bytes[3] == 0x04;

/// 读第一个工作表，所有单元格转成字符串。
List<List<String>>? _readXlsx(List<int> bytes) {
  try {
    final excel = Excel.decodeBytes(bytes);
    if (excel.tables.isEmpty) return null;
    final table = excel.tables[excel.tables.keys.first];
    if (table == null) return null;
    return [
      for (final row in table.rows)
        [for (final cell in row) '${cell?.value ?? ''}'.trim()],
    ];
  } catch (_) {
    return null;
  }
}

/// 表头行最多往后找这么多行（支付宝/微信前面都有说明文字）。
const _maxHeaderScan = 30;

/// 找表头行：含「交易时间」，或同时含「类型/金额/时间」。
int _findHeaderIndex(List<List<String>> matrix) {
  final limit = matrix.length < _maxHeaderScan ? matrix.length : _maxHeaderScan;
  for (var i = 0; i < limit; i++) {
    final cells = matrix[i].map((c) => c.trim()).toList();
    if (cells.any((c) => c == '交易时间')) return i;
    final hasType = cells.any((c) => c == '类型' || c == 'Type');
    final hasAmount = cells.any((c) => c == '金额' || c == 'Amount');
    final hasTime = cells.any((c) => c == '时间' || c == 'Time');
    if (hasType && hasAmount && hasTime) return i;
  }
  return -1;
}

StatementKind detectKind(List<List<String>> matrix) {
  final headerIndex = _findHeaderIndex(matrix);
  if (headerIndex < 0) return StatementKind.unknown;

  final header = matrix[headerIndex].map((c) => c.trim()).toList();
  final preamble = [
    for (var i = 0; i < headerIndex; i++) ...matrix[i],
  ].join(' ');

  final hasFlow = header.any((c) => c == '收/支' || c == '收支');
  final hasAlipayColumn = header.any((c) => c == '交易分类' || c == '收/付款方式');
  final hasWechatColumn = header.any((c) => c == '支付方式' || c == '当前状态');

  if (hasFlow) {
    if (preamble.contains('支付宝') || hasAlipayColumn) {
      return StatementKind.alipay;
    }
    if (preamble.contains('微信') || hasWechatColumn) {
      return StatementKind.wechat;
    }
  }
  if (header.any((c) => c == '类型' || c == 'Type')) {
    return StatementKind.beecount;
  }
  return StatementKind.unknown;
}

StatementParse _parseMatrix(
  List<List<String>> matrix, {
  String fileName = '',
}) {
  final kind = detectKind(matrix);
  final headerIndex = _findHeaderIndex(matrix);

  switch (kind) {
    case StatementKind.alipay:
      return StatementParse(
        kind: kind,
        result: _parseStatement(matrix, headerIndex, kind),
      );
    case StatementKind.wechat:
      return StatementParse(
        kind: kind,
        result: _parseStatement(matrix, headerIndex, kind),
      );
    case StatementKind.beecount:
      final text = const ListToCsvConverter().convert(matrix);
      return StatementParse(
        kind: kind,
        result: parseBeeCountCsv(utf8.encode(text)),
      );
    case StatementKind.unknown:
      return StatementParse(
        kind: kind,
        result: ParseResult(
          rows: const [],
          skipped: const [],
          fatal: '认不出这份文件的格式。支持：BeeCount 导出（zip/CSV）、'
              '支付宝账单、微信支付账单、Excel（.xlsx）',
          totalRows: matrix.isEmpty ? 0 : matrix.length - 1,
        ),
      );
  }
}

/// 支付宝/微信共用一套行解析：列名定位 + 收支类型 + 分类映射 + 跳过规则。
ParseResult _parseStatement(
  List<List<String>> matrix,
  int headerIndex,
  StatementKind kind,
) {
  final header = [
    for (final cell in matrix[headerIndex]) cell.trim(),
  ];

  int columnAt(List<String> names) {
    for (final name in names) {
      final at = header.indexOf(name);
      if (at >= 0) return at;
    }
    return -1;
  }

  final timeAt = columnAt(const ['交易时间']);
  final flowAt = columnAt(const ['收/支', '收支']);
  final amountAt = columnAt(const ['金额', '金额(元)']);
  final noteAt = columnAt(
    kind == StatementKind.alipay
        ? const ['商品说明', '交易对方']
        : const ['商品', '交易对方'],
  );
  final categoryAt = columnAt(const ['交易分类']);
  final statusAt = columnAt(const ['交易状态', '当前状态']);

  if (timeAt < 0 || flowAt < 0 || amountAt < 0) {
    return ParseResult(
      rows: const [],
      skipped: const [],
      fatal: '账单缺少必需列：${[
        if (timeAt < 0) '交易时间',
        if (flowAt < 0) '收/支',
        if (amountAt < 0) '金额',
      ].join('、')}',
    );
  }

  final rows = <ParsedRow>[];
  final skipped = <SkippedRow>[];
  final total = matrix.length - headerIndex - 1;

  for (var i = headerIndex + 1; i < matrix.length; i++) {
    final cells = matrix[i];
    if (cells.every((c) => c.trim().isEmpty)) continue;
    final lineNumber = i + 1;
    final summary = [
      if (noteAt >= 0 && noteAt < cells.length) cells[noteAt].trim(),
      if (amountAt < cells.length) cells[amountAt].trim(),
    ].join(' · ');

    String cell(int at) =>
        at >= 0 && at < cells.length ? cells[at].trim() : '';

    final flow = cell(flowAt);
    if (flow == '不计收支' || flow == '/' || flow.isEmpty) {
      skipped.add(SkippedRow(
        lineNumber: lineNumber,
        reason: flow.isEmpty ? '缺收支类型' : '不计收支，跳过',
        summary: summary,
      ));
      continue;
    }

    final status = cell(statusAt);
    if (status.contains('退款') || status.contains('关闭') || status.contains('失败')) {
      skipped.add(SkippedRow(
        lineNumber: lineNumber,
        reason: '交易未完成（$status），跳过',
        summary: summary,
      ));
      continue;
    }

    final isIncome = flow == '收入';
    if (!isIncome && flow != '支出') {
      skipped.add(SkippedRow(
        lineNumber: lineNumber,
        reason: '认不出收支类型「$flow」',
        summary: summary,
      ));
      continue;
    }

    final amount = parseAmountToCents(_cleanAmount(cell(amountAt)));
    if (amount == null || amount <= 0) {
      skipped.add(SkippedRow(
        lineNumber: lineNumber,
        reason: '金额读不出来「${cell(amountAt)}」',
        summary: summary,
      ));
      continue;
    }

    final happenedAt = parseBeeCountTime(cell(timeAt));
    if (happenedAt == null) {
      skipped.add(SkippedRow(
        lineNumber: lineNumber,
        reason: '时间读不出来「${cell(timeAt)}」',
        summary: summary,
      ));
      continue;
    }

    final category = mapStatementCategory(
      rawCategory: cell(categoryAt),
      isIncome: isIncome,
      counterparty: cell(noteAt),
    );

    rows.add(
      ParsedRow(
        lineNumber: lineNumber,
        type: isIncome ? EntryType.income : EntryType.expense,
        categoryName: category,
        amountCents: amount,
        happenedAt: happenedAt,
        note: cell(noteAt),
        accountName: kind == StatementKind.alipay ? '支付宝' : '微信支付',
      ),
    );
  }

  return ParseResult(rows: rows, skipped: skipped, totalRows: total);
}

/// 去掉 `¥`、`元`、千分位逗号与空格。
String _cleanAmount(String raw) => raw
    .replaceAll('¥', '')
    .replaceAll('￥', '')
    .replaceAll('元', '')
    .replaceAll(',', '')
    .replaceAll(' ', '')
    .trim();

/// 对方分类 → 本地分类名。匹配不到时兜底，不报错。
String mapStatementCategory({
  required String rawCategory,
  required bool isIncome,
  String counterparty = '',
}) {
  final haystack = '$rawCategory $counterparty';
  const expenseMap = <String, String>{
    '餐饮': '餐饮',
    '美食': '餐饮',
    '交通': '交通',
    '出行': '交通',
    '服饰': '购物',
    '日用': '购物',
    '购物': '购物',
    '医疗': '医疗',
    '健康': '医疗',
    '教育': '教育',
    '培训': '教育',
    '酒店': '旅行',
    '旅游': '旅行',
    '运动': '运动',
    '户外': '运动',
    '数码': '数码',
    '电器': '数码',
    '住房': '居家',
    '物业': '居家',
    '宠物': '宠物',
  };
  const incomeMap = <String, String>{
    '工资': '工资',
    '薪': '工资',
    '红包': '红包',
    '理财': '理财',
    '投资': '理财',
    '奖金': '奖金',
    '兼职': '兼职',
  };

  final table = isIncome ? incomeMap : expenseMap;
  for (final entry in table.entries) {
    if (haystack.contains(entry.key)) return entry.value;
  }
  return isIncome ? '其他收入' : '其他';
}
