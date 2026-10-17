import 'dart:typed_data';

import 'package:archive/archive.dart';

import '../../data/repositories/attachment_repository.dart';
import '../../data/repositories/transaction_repository.dart';
import 'bee_count_csv_writer.dart';

/// 一次导出的产物：文件名、内容与规模，页面直接拿来展示与保存。
class ExportFile {
  const ExportFile({
    required this.fileName,
    required this.bytes,
    required this.entryCount,
    required this.imageCount,
  });

  final String fileName;
  final Uint8List bytes;
  final int entryCount;
  final int imageCount;

  int get byteSize => bytes.length;

  /// 人读的大小（`18.7 MB`）。用 1024 进制，和系统文件管理器一致。
  String get readableSize {
    final bytes = byteSize;
    if (bytes < 1024) return '$bytes B';
    const units = ['KB', 'MB', 'GB'];
    var value = bytes / 1024;
    var unit = 0;
    while (value >= 1024 && unit < units.length - 1) {
      value /= 1024;
      unit++;
    }
    return '${value.toStringAsFixed(value >= 10 ? 0 : 1)} ${units[unit]}';
  }
}

/// 导出账本：CSV（可回灌）与完整备份 zip（含全部票据）。
///
/// 两种产物都复用**导入端的格式约定**，所以 `导出 → 清库 → 导入` 是可测闭环。
class ExportService {
  ExportService({
    required TransactionRepository transactions,
    required AttachmentRepository attachments,
    DateTime Function()? clock,
  })  : _transactions = transactions,
        _attachments = attachments,
        _clock = clock ?? DateTime.now;

  final TransactionRepository _transactions;
  final AttachmentRepository _attachments;
  final DateTime Function() _clock;

  /// `20261018_011500`
  String get _stamp {
    final now = _clock();
    String two(int v) => v.toString().padLeft(2, '0');
    final date = '${now.year}${two(now.month)}${two(now.day)}';
    final time = '${two(now.hour)}${two(now.minute)}${two(now.second)}';
    return '${date}_$time';
  }

  /// 只导账目：小、可读、可被 BeeCount 与本 App 再导入。
  Future<ExportFile> buildCsv() async {
    final rows = await _transactions.exportRows();
    return ExportFile(
      fileName: 'beecount_$_stamp.csv',
      bytes: buildBeeCountCsv(rows),
      entryCount: rows.length,
      imageCount: 0,
    );
  }

  /// 完整备份：zip 内是 csv + `beecount_attachments_*.tar.gz`（`images/` 下是票据原件）。
  Future<ExportFile> buildBackup() async {
    final rows = await _transactions.exportRows();
    final stamp = _stamp;
    final csvBytes = buildBeeCountCsv(rows);

    final files = await _attachments.allFiles();
    final tar = Archive();
    for (final file in files) {
      final bytes = await file.readAsBytes();
      final name = file.uri.pathSegments.last;
      tar.addFile(ArchiveFile('images/$name', bytes.length, bytes));
    }
    // 空附件也要有合法的 tar（0 字节的 gzip 无法被导入端识别）
    final tarBytes = TarEncoder().encode(tar);
    final gz = GZipEncoder().encode(tarBytes)!;

    final zip = Archive()
      ..addFile(
        ArchiveFile('beecount_$stamp.csv', csvBytes.length, csvBytes),
      )
      ..addFile(
        ArchiveFile(
          'beecount_attachments_$stamp.tar.gz',
          gz.length,
          gz,
        ),
      );

    return ExportFile(
      fileName: 'beancount_backup_$stamp.zip',
      bytes: Uint8List.fromList(ZipEncoder().encode(zip)!),
      entryCount: rows.length,
      imageCount: files.length,
    );
  }
}
