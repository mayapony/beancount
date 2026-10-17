import 'package:intl/intl.dart';

import 'import_models.dart';

/// 导入结果：数字要能一一对上（总行数 = 成功 + 跳过 + 失败）。
class ImportReport {
  const ImportReport({
    required this.totalRows,
    required this.inserted,
    required this.skipped,
    required this.failures,
    required this.skipReasons,
    required this.attachmentsSaved,
    required this.attachmentsMissing,
    required this.newCategories,
    required this.newAccounts,
    required this.newTags,
    required this.elapsed,
  });

  final int totalRows;
  final int inserted;
  final int skipped;
  final List<SkippedRow> failures;
  final Map<String, int> skipReasons;
  final int attachmentsSaved;
  final int attachmentsMissing;
  final int newCategories;
  final int newAccounts;
  final int newTags;
  final Duration elapsed;

  int get failed => failures.length;

  /// 复制到剪贴板的纯文本报告。
  String toText() {
    final buffer = StringBuffer()
      ..writeln('BeeCount 导入报告')
      ..writeln('总行数：$totalRows')
      ..writeln('成功：$inserted')
      ..writeln('跳过：$skipped')
      ..writeln('失败：$failed');

    if (skipReasons.isNotEmpty) {
      buffer.writeln('跳过原因：');
      for (final entry in skipReasons.entries) {
        buffer.writeln('  · ${entry.key}：${entry.value} 行');
      }
    }
    if (failures.isNotEmpty) {
      buffer.writeln('失败明细：');
      for (final item in failures) {
        buffer.writeln('  第 ${item.lineNumber} 行：${item.reason}');
      }
    }
    buffer
      ..writeln('附件：写入 $attachmentsSaved 张，缺失 $attachmentsMissing 张')
      ..writeln('新建分类 $newCategories · 账户 $newAccounts · 标签 $newTags')
      ..writeln('用时：${(elapsed.inMilliseconds / 1000).toStringAsFixed(1)}s');
    return buffer.toString();
  }

  String get elapsedLabel => '${(elapsed.inMilliseconds / 1000).toStringAsFixed(1)}s';
}

/// 给报告里"用时"用的格式化（保留给 UI 展示毫秒级细节）。
String formatDuration(Duration d) => NumberFormat('0.0').format(
      d.inMilliseconds / 1000,
    );
