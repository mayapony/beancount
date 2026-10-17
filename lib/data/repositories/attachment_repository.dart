import 'dart:io';
import 'package:drift/drift.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../db/app_database.dart';

/// 附件仓储：图片文件写在 `<appDocs>/attachments/`，库里只存文件名。
///
/// 三个约束：
/// 1. 先落盘、再写记录——不产生"有记录没图"；
/// 2. 同名文件只存一份（真实导出里两笔交易共用一个 sha 文件名）；
/// 3. 删记录时按引用计数回收文件，别误删别人还在用的图。
class AttachmentRepository {
  AttachmentRepository(this._db, {Directory? directory})
      : _directoryOverride = directory,
        _resolved = directory;

  final AppDatabase _db;

  /// 单测 / 截图脚本可注入临时目录；App 里为 null，走应用文档目录。
  final Directory? _directoryOverride;

  /// 已解析的附件目录；注入目录时直接用它，避免在首帧做 IO。
  Directory? _resolved;

  /// 解析并缓存附件目录（页面在 initState 里 await 一次，之后可同步取路径）。
  Future<Directory> ensureReady() async {
    final existing = _resolved;
    if (existing != null) {
      if (!await existing.exists()) {
        await existing.create(recursive: true);
      }
      return existing;
    }

    final dir = _directoryOverride ??
        Directory(p.join(
          (await getApplicationDocumentsDirectory()).path,
          'attachments',
        ));
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    _resolved = dir;
    return dir;
  }

  /// 同步取文件（目录还没解析时返回 null，用于列表渲染）。
  File? fileFor(String fileName) {
    final dir = _resolved;
    if (dir == null) return null;
    return File(p.join(dir.path, fileName));
  }

  Future<List<Attachment>> attachmentsOf(String transactionId) {
    final query = _db.select(_db.attachments)
      ..where((t) => t.transactionId.equals(transactionId))
      ..orderBy([(t) => OrderingTerm(expression: t.sortOrder)]);
    return query.get();
  }

  /// 新增一张图片：同名文件已存在则复用，不重复占磁盘。
  Future<Attachment> add({
    required String transactionId,
    required List<int> bytes,
    required String fileName,
    String? originalName,
    int sortOrder = 0,
  }) async {
    final safeName = _sanitize(fileName);
    final dir = await ensureReady();
    final file = File(p.join(dir.path, safeName));
    if (!await file.exists() || await file.length() != bytes.length) {
      await file.writeAsBytes(bytes, flush: true);
    }

    final id = 'att-${DateTime.now().microsecondsSinceEpoch}-${_seq++}';
    await _db.into(_db.attachments).insert(
          AttachmentsCompanion.insert(
            id: id,
            transactionId: transactionId,
            fileName: safeName,
            originalName: Value(originalName),
            fileSize: Value(bytes.length),
            sortOrder: Value(sortOrder),
          ),
        );
    return (await (_db.select(_db.attachments)
              ..where((t) => t.id.equals(id)))
            .getSingle());
  }

  /// 删除一条附件记录；该文件名再无引用时才删磁盘文件。
  Future<void> remove(String attachmentId) async {
    final row = await (_db.select(_db.attachments)
          ..where((t) => t.id.equals(attachmentId)))
        .getSingleOrNull();
    if (row == null) return;
    await (_db.delete(_db.attachments)..where((t) => t.id.equals(attachmentId)))
        .go();
    await _deleteFileIfUnreferenced(row.fileName);
  }

  /// 删除一笔交易的全部附件（交易本身由仓储层负责删除）。
  Future<void> removeForTransaction(String transactionId) async {
    final rows = await attachmentsOf(transactionId);
    for (final row in rows) {
      await remove(row.id);
    }
  }

  /// 清理没有任何记录引用的文件（导入回滚后可能留下孤儿文件）。
  Future<int> sweepOrphans() async {
    final dir = await ensureReady();
    final referenced = {
      for (final a in await _db.select(_db.attachments).get()) a.fileName,
    };
    var removed = 0;
    await for (final entity in dir.list()) {
      if (entity is! File) continue;
      final name = p.basename(entity.path);
      if (referenced.contains(name)) continue;
      await entity.delete();
      removed++;
    }
    return removed;
  }

  static int _seq = 0;

  Future<void> _deleteFileIfUnreferenced(String fileName) async {
    final row = await _db
        .customSelect(
          'SELECT COUNT(*) AS c FROM attachments WHERE file_name = ?',
          variables: [Variable.withString(fileName)],
        )
        .getSingle();
    if (row.read<int>('c') > 0) return;
    final file = fileFor(fileName);
    if (file != null && await file.exists()) {
      await file.delete();
    }
  }

  /// 附件名只允许是纯文件名：带路径分隔符或 `..` 的一律拒绝，
  /// 由调用方（导入）记 warning 后跳过，避免写到目录外。
  String _sanitize(String fileName) {
    final name = fileName.trim();
    if (name.isEmpty ||
        name == '.' ||
        name == '..' ||
        name.contains('/') ||
        name.contains('\\') ||
        name.contains('..')) {
      throw ArgumentError.value(fileName, 'fileName', '非法附件名');
    }
    return name;
  }
}
