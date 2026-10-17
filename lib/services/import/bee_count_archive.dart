import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';

/// 附件包里的一张图：文件名 + 原始字节 + 可选原始名。
class ExtractedAttachment {
  const ExtractedAttachment({
    required this.fileName,
    required this.bytes,
    this.originalName,
    this.fileSize,
  });

  final String fileName;
  final List<int> bytes;
  final String? originalName;
  final int? fileSize;
}

/// 从一个导出文件里拆出来的东西。
class ExtractedExport {
  const ExtractedExport({
    required this.csvBytes,
    required this.attachments,
    this.warnings = const <String>[],
    this.fatal,
    this.zipName = '',
  });

  final List<int> csvBytes;
  final List<ExtractedAttachment> attachments;
  final List<String> warnings;
  final String? fatal;
  final String zipName;

  bool get ok => fatal == null;
}

/// 读取 BeeCount 的导出：可以直接给 CSV 的字节，也可以给完整备份 zip。
///
/// zip 里的约定（见 BeeCount `export_page.dart`）：
/// - `beecount_<时间>.csv`
/// - `beecount_attachments_<id>.tar.gz`（内含 `images/<fileName>` 与 `metadata.json`）
ExtractedExport extractBeeCountExport(List<int> bytes, {String name = ''}) {
  if (!_looksLikeZip(bytes)) {
    return ExtractedExport(csvBytes: bytes, attachments: const [], zipName: name);
  }

  try {
    final zip = ZipDecoder().decodeBytes(bytes);
    Uint8List? csv;
    Uint8List? tarGz;
    var csvName = '';

    for (final entry in zip.files) {
      if (!entry.isFile) continue;
      final entryName = entry.name;
      final lower = entryName.toLowerCase();
      if (lower.endsWith('.csv') && csv == null) {
        csv = Uint8List.fromList(entry.content as List<int>);
        csvName = entryName;
      } else if (lower.endsWith('.tar.gz') && tarGz == null) {
        tarGz = Uint8List.fromList(entry.content as List<int>);
      }
    }

    if (csv == null) {
      return ExtractedExport(
        csvBytes: const [],
        attachments: const [],
        fatal: '压缩包里没有找到 CSV（应该有一个 beecount_*.csv）',
        zipName: name,
      );
    }

    final warnings = <String>[];
    final attachments = <ExtractedAttachment>[];
    if (tarGz != null) {
      attachments.addAll(_readAttachmentTar(tarGz, warnings));
    } else {
      warnings.add('压缩包里没有附件包，只导入文字记录');
    }

    return ExtractedExport(
      csvBytes: csv,
      attachments: attachments,
      warnings: warnings,
      zipName: name.isEmpty ? csvName : '$name（$csvName）',
    );
  } catch (error) {
    return ExtractedExport(
      csvBytes: const [],
      attachments: const [],
      fatal: '压缩包打不开：$error',
      zipName: name,
    );
  }
}

List<ExtractedAttachment> _readAttachmentTar(
  Uint8List tarGz,
  List<String> warnings,
) {
  final tarBytes = GZipDecoder().decodeBytes(tarGz);
  final tar = TarDecoder().decodeBytes(tarBytes);

  final meta = <String, Map<String, dynamic>>{};
  final images = <String, List<int>>{};

  for (final entry in tar.files) {
    if (!entry.isFile) continue;
    final entryName = entry.name.replaceAll('\\', '/');
    if (entryName.endsWith('metadata.json')) {
      try {
        final decoded = json.decode(utf8.decode(entry.content as List<int>));
        if (decoded is Map<String, dynamic>) {
          for (final item in (decoded['attachments'] as List? ?? const [])) {
            if (item is Map<String, dynamic> && item['fileName'] is String) {
              meta[item['fileName'] as String] = item;
            }
          }
        }
      } catch (_) {
        warnings.add('metadata.json 读不出来，附件名与大小按文件名推断');
      }
    } else if (entryName.startsWith('images/')) {
      final fileName = entryName.substring('images/'.length);
      if (fileName.isEmpty) continue;
      images[fileName] = entry.content as List<int>;
    }
  }

  return [
    for (final entry in images.entries)
      ExtractedAttachment(
        fileName: entry.key,
        bytes: entry.value,
        originalName: meta[entry.key]?['originalName'] as String?,
        fileSize: (meta[entry.key]?['fileSize'] as num?)?.toInt(),
      ),
  ];
}

bool _looksLikeZip(List<int> bytes) =>
    bytes.length >= 4 &&
    bytes[0] == 0x50 && // P
    bytes[1] == 0x4B && // K
    bytes[2] == 0x03 &&
    bytes[3] == 0x04;
