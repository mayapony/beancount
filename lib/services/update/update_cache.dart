import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// 更新包缓存目录：`<cache>/update/`。
///
/// 只暴露给下载器与清理逻辑；Web 构建不会 import 这个文件。
class UpdateCache {
  UpdateCache({Future<Directory> Function()? root, DateTime Function()? now})
      : _root = root ?? getTemporaryDirectory,
        _now = now ?? DateTime.now;

  static const directoryName = 'update';
  static const apkName = 'app-release.apk';
  static const partSuffix = '.part';

  final Future<Directory> Function() _root;
  final DateTime Function() _now;

  Future<Directory> directory() async {
    final root = await _root();
    final dir = Directory(p.join(root.path, directoryName));
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  /// 删除过期缓存；正在下载的 `.part` 只要还新鲜就不动。
  Future<void> clean() async {
    final dir = await directory();
    final now = _now();
    await for (final entity in dir.list()) {
      if (entity is! File) continue;
      final stat = await entity.stat();
      final age = now.difference(stat.modified);
      final name = p.basename(entity.path);
      final isPart = name.endsWith(partSuffix);
      final maxAge =
          isPart ? const Duration(days: 1) : const Duration(days: 7);
      if (age <= maxAge) continue;
      try {
        await entity.delete();
      } on FileSystemException {
        // 清理失败不影响启动；下次再试。
      }
    }
  }
}
