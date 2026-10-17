import 'dart:convert';

import 'package:archive/archive.dart';
import 'package:bean_count/services/import/bee_count_archive.dart';
import 'package:flutter_test/flutter_test.dart';

List<int> _csv() => utf8.encode(
      '类型,分类,金额,时间\n支出,餐饮,12.34,  2026-10-17 12:30:00  \n',
    );

List<int> _buildZip({bool withAttachments = true}) {
  final csv = _csv();
  final zip = Archive()
    ..addFile(ArchiveFile('beecount_20260101_000000.csv', csv.length, csv));

  if (withAttachments) {
    final tar = Archive()
      ..addFile(ArchiveFile('images/sha_a.jpg', 3, <int>[1, 2, 3]))
      ..addFile(ArchiveFile('images/sha_b.jpg', 4, <int>[4, 5, 6, 7]));
    final meta = utf8.encode(json.encode({
      'version': 3,
      'count': 2,
      'attachments': [
        {'fileName': 'sha_a.jpg', 'originalName': 'Screenshot_a.jpg', 'fileSize': 3},
        {'fileName': 'sha_b.jpg', 'originalName': 'Screenshot_b.jpg', 'fileSize': 4},
      ],
    }));
    tar.addFile(ArchiveFile('metadata.json', meta.length, meta));

    final gz = GZipEncoder().encode(TarEncoder().encode(tar))!;
    zip.addFile(
      ArchiveFile('beecount_attachments_1792239580042.tar.gz', gz.length, gz),
    );
  }

  return ZipEncoder().encode(zip)!;
}

void main() {
  test('zip 里能取出 CSV、图片与原始文件名', () {
    final result = extractBeeCountExport(_buildZip(), name: 'BeeCount.zip');

    expect(result.ok, isTrue, reason: result.fatal);
    expect(result.csvBytes, isNotEmpty);
    expect(result.attachments, hasLength(2));

    final first = result.attachments.firstWhere((a) => a.fileName == 'sha_a.jpg');
    expect(first.bytes, [1, 2, 3]);
    expect(first.originalName, 'Screenshot_a.jpg');
    expect(first.fileSize, 3);
  });

  test('只有 CSV 的 zip：能导入文字，提示没有附件包', () {
    final result = extractBeeCountExport(_buildZip(withAttachments: false));

    expect(result.ok, isTrue);
    expect(result.csvBytes, isNotEmpty);
    expect(result.attachments, isEmpty);
    expect(result.warnings.single, contains('没有附件包'));
  });

  test('直接给 CSV 字节也能用', () {
    final result = extractBeeCountExport(_csv(), name: 'x.csv');

    expect(result.ok, isTrue);
    expect(result.attachments, isEmpty);
    expect(utf8.decode(result.csvBytes), contains('支出'));
  });

  test('坏 zip 给出可读的失败原因，而不是抛异常', () {
    final result = extractBeeCountExport(
      <int>[0x50, 0x4B, 0x03, 0x04, 0, 0, 0, 0],
      name: 'broken.zip',
    );

    expect(result.ok, isFalse);
    expect(result.fatal, contains('压缩包打不开'));
  });
}
