import 'dart:convert';
import 'dart:typed_data';

import 'package:csv/csv.dart';

import '../../data/db/enums.dart';
import '../../data/repositories/transaction_repository.dart';

/// 导出 CSV 的表头：与 `lib/services/import/bee_count_csv.dart` 的别名表一一对应，
/// 顺序也照抄 BeeCount 的导出，保证「导出 → 导入」闭环。
const kBeeCountExportHeader = <String>[
  '类型',
  '分类',
  '二级分类',
  '金额',
  '币种',
  '账户',
  '转出账户',
  '转入账户',
  '备注',
  '时间',
  '标签',
  '附件',
];

/// 把账本写成 BeeCount 格式的 CSV（UTF-8 带 BOM、`\n` 换行）。
Uint8List buildBeeCountCsv(List<ExportRow> rows) {
  final matrix = <List<String>>[
    kBeeCountExportHeader,
    for (final row in rows) _cellsOf(row),
  ];
  final text = const ListToCsvConverter(eol: '\n').convert(matrix);

  // BOM：Excel / WPS 打开中文表头才不乱码；导入端会剥掉
  return Uint8List.fromList(<int>[0xEF, 0xBB, 0xBF, ...utf8.encode(text)]);
}

List<String> _cellsOf(ExportRow row) {
  final transaction = row.transaction;
  final path = row.categoryPath;
  return [
    transaction.type == EntryType.income ? '收入' : '支出',
    path.isNotEmpty ? path.first : '未分类',
    path.length > 1 ? path[1] : '',
    formatCents(transaction.amountCents),
    'CNY',
    row.accountName ?? '',
    '', // 转出账户：转账不在本次范围，占位保持列对齐
    '', // 转入账户
    transaction.note,
    formatBeeCountTime(transaction.happenedAt),
    row.tags.join(','),
    row.attachmentNames.join(','),
  ];
}

/// 整数分 → `38.50`。不走 double，避免 `3850 / 100 = 38.499…`。
String formatCents(int cents) {
  final sign = cents < 0 ? '-' : '';
  final abs = cents.abs();
  final fraction = (abs % 100).toString().padLeft(2, '0');
  return '$sign${abs ~/ 100}.$fraction';
}

/// `YYYY-MM-DD HH:mm:ss`（导入端使用的格式）。
String formatBeeCountTime(DateTime time) {
  String two(int value) => value.toString().padLeft(2, '0');
  return '${time.year}-${two(time.month)}-${two(time.day)} '
      '${two(time.hour)}:${two(time.minute)}:${two(time.second)}';
}
