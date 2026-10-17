import 'dart:convert';

import 'package:csv/csv.dart';

import '../../data/db/enums.dart';
import 'import_models.dart';

/// BeeCount 导出文件的表头别名：按**列名**取值，所以列顺序变化不影响。
const _headerAliases = <String, List<String>>{
  'type': ['类型', 'Type'],
  'category': ['分类', 'Category'],
  'subcategory': ['二级分类', 'Subcategory'],
  'amount': ['金额', 'Amount'],
  'currency': ['币种', 'Currency'],
  'account': ['账户', 'Account'],
  'fromAccount': ['转出账户', 'From Account'],
  'toAccount': ['转入账户', 'To Account'],
  'note': ['备注', 'Note'],
  'time': ['时间', 'Time'],
  'tags': ['标签', 'Tags'],
  'attachments': ['附件', 'Attachments'],
};

/// 必需列：缺一个就整批拒绝，避免"导入了一半才发现字段错位"。
const _required = <String>['type', 'category', 'amount', 'time'];

/// 解析 BeeCount 导出的 CSV（UTF-8 带 BOM、逗号分隔、首行表头）。
///
/// 单行坏数据只跳过该行并记行号，不中止整批；只有"缺必需列"才是致命的。
ParseResult parseBeeCountCsv(List<int> bytes) {
  var text = utf8.decode(_stripBom(bytes), allowMalformed: true);
  text = text.replaceAll('\r\n', '\n').replaceAll('\r', '\n');

  final matrix = CsvToListConverter(
    shouldParseNumbers: false,
    eol: '\n',
  ).convert(text);

  if (matrix.isEmpty) {
    return const ParseResult(
      rows: [],
      skipped: [],
      fatal: '文件是空的',
    );
  }

  final header = matrix.first.map((c) => '$c'.trim()).toList();
  final index = <String, int>{};
  for (final entry in _headerAliases.entries) {
    for (final alias in entry.value) {
      final at = header.indexOf(alias);
      if (at >= 0) {
        index[entry.key] = at;
        break;
      }
    }
  }

  final missing = [
    for (final key in _required)
      if (!index.containsKey(key)) _headerAliases[key]!.first,
  ];
  if (missing.isNotEmpty) {
    return ParseResult(
      rows: const [],
      skipped: const [],
      fatal: '缺少必需列：${missing.join('、')}',
      totalRows: matrix.length - 1,
    );
  }

  final rows = <ParsedRow>[];
  final skipped = <SkippedRow>[];
  final total = matrix.length - 1;

  for (var i = 1; i < matrix.length; i++) {
    final raw = matrix[i];
    final lineNumber = i + 1;
    if (raw.every((cell) => '$cell'.trim().isEmpty)) continue; // 空行不算数据

    String cell(String key) {
      final at = index[key];
      if (at == null || at >= raw.length) return '';
      return '${raw[at]}'.trim();
    }

    final typeRaw = cell('type');
    final type = _parseType(typeRaw);
    if (type == null) {
      if (_isTransfer(typeRaw)) {
        skipped.add(SkippedRow(
          lineNumber: lineNumber,
          reason: '转账暂不支持',
          summary: cell('note'),
        ));
      } else {
        skipped.add(SkippedRow(
          lineNumber: lineNumber,
          reason: '未知类型「$typeRaw」',
          summary: cell('note'),
        ));
      }
      continue;
    }

    final categoryName = cell('category');
    if (categoryName.isEmpty) {
      skipped.add(SkippedRow(
        lineNumber: lineNumber,
        reason: '缺少分类',
        summary: cell('note'),
      ));
      continue;
    }

    final amountRaw = cell('amount').replaceAll(',', '');
    final amountCents = parseAmountToCents(amountRaw);
    if (amountCents == null) {
      skipped.add(SkippedRow(
        lineNumber: lineNumber,
        reason: '金额无法解析「$amountRaw」',
        summary: cell('note'),
      ));
      continue;
    }
    if (amountCents <= 0) {
      skipped.add(SkippedRow(
        lineNumber: lineNumber,
        reason: '金额必须大于 0',
        summary: cell('note'),
      ));
      continue;
    }

    final happenedAt = parseBeeCountTime(cell('time'));
    if (happenedAt == null) {
      skipped.add(SkippedRow(
        lineNumber: lineNumber,
        reason: '时间无法解析「${cell('time')}」',
        summary: cell('note'),
      ));
      continue;
    }

    rows.add(
      ParsedRow(
        lineNumber: lineNumber,
        type: type,
        categoryName: categoryName,
        subcategoryName: cell('subcategory'),
        amountCents: amountCents,
        currency: cell('currency').isEmpty ? 'CNY' : cell('currency'),
        accountName: cell('account'),
        note: cell('note'),
        happenedAt: happenedAt,
        tags: _splitMulti(cell('tags')),
        attachments: _splitMulti(cell('attachments')),
      ),
    );
  }

  return ParseResult(
    rows: rows,
    skipped: skipped,
    totalRows: total,
  );
}

List<int> _stripBom(List<int> bytes) {
  if (bytes.length >= 3 &&
      bytes[0] == 0xEF &&
      bytes[1] == 0xBB &&
      bytes[2] == 0xBF) {
    return bytes.sublist(3);
  }
  return bytes;
}

EntryType? _parseType(String raw) {
  switch (raw) {
    case '收入':
    case 'Income':
    case 'income':
      return EntryType.income;
    case '支出':
    case 'Expense':
    case 'expense':
      return EntryType.expense;
    default:
      return null;
  }
}

bool _isTransfer(String raw) => raw == '转账' || raw == 'Transfer' || raw == 'transfer';

/// 金额字符串 → 整数分。不用 `double * 100`，避免 `38.5 * 100 = 3849.999…`。
int? parseAmountToCents(String raw) {
  final text = raw.trim();
  if (text.isEmpty) return null;
  final match = RegExp(r'^-?\d+(\.\d{1,2})?$').firstMatch(text);
  if (match == null) return null;

  final negative = text.startsWith('-');
  final body = negative ? text.substring(1) : text;
  final parts = body.split('.');
  final yuan = int.tryParse(parts[0]);
  if (yuan == null) return null;
  final fraction = parts.length > 1 ? parts[1].padRight(2, '0') : '00';
  final cents = yuan * 100 + int.parse(fraction);
  return negative ? -cents : cents;
}

/// BeeCount 的时间是 `YYYY-MM-DD HH:mm:ss`，导出时**前后各加两个空格**。
DateTime? parseBeeCountTime(String raw) {
  final text = raw.trim();
  if (text.isEmpty) return null;

  for (final pattern in [
    RegExp(r'^(\d{4})-(\d{2})-(\d{2})[ T](\d{2}):(\d{2}):(\d{2})$'),
    RegExp(r'^(\d{4})-(\d{2})-(\d{2})[ T](\d{2}):(\d{2})$'),
    RegExp(r'^(\d{4})/(\d{2})/(\d{2})[ T](\d{2}):(\d{2})$'),
    RegExp(r'^(\d{4})/(\d{2})/(\d{2})[ T](\d{2}):(\d{2}):(\d{2})$'),
  ]) {
    final m = pattern.firstMatch(text);
    if (m == null) continue;
    final hasSeconds = m.groupCount >= 6 && m.group(6) != null;
    final year = int.parse(m.group(1)!);
    final month = int.parse(m.group(2)!);
    final day = int.parse(m.group(3)!);
    final hour = int.parse(m.group(4)!);
    final minute = int.parse(m.group(5)!);
    final second = hasSeconds ? int.parse(m.group(6)!) : 0;
    if (month < 1 || month > 12 || day < 1 || day > 31) return null;
    return DateTime(year, month, day, hour, minute, second);
  }
  return null;
}

List<String> _splitMulti(String raw) {
  if (raw.trim().isEmpty) return const [];
  final seen = <String>{};
  final out = <String>[];
  for (final part in raw.split(',')) {
    final name = part.trim();
    if (name.isEmpty || !seen.add(name)) continue;
    out.add(name);
  }
  return out;
}
