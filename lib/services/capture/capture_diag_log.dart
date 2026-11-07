library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

/// 运行记录的文件落点：一行一条 JSON。
///
/// 页面之外再落一份的原因很实际——排查时通常连着 adb，`adb pull` 一下就能拿到
/// 全量，不必解锁手机翻页面；App 被系统杀掉后页面上的环形也没了，文件还在。
///
/// 单文件到 [maxBytes] 就滚成 `events.log.1`（只留一份旧文件），新文件从头写。
class CaptureDiagLogFile {
  CaptureDiagLogFile(
    this.directory, {
    this.maxBytes = kMaxBytes,
    this.fileName = 'events.log',
  });

  final Directory directory;
  final int maxBytes;
  final String fileName;

  static const kMaxBytes = 512 * 1024;

  /// 串行写：并发调用排队，避免两行 JSON 交错成半行。
  Future<void> _queue = Future<void>.value();

  File get file => File('${directory.path}${Platform.pathSeparator}$fileName');

  File get rolledFile =>
      File('${directory.path}${Platform.pathSeparator}$fileName.1');

  /// 追加一行；写失败只吞掉，不向外抛（记录不能影响业务）。
  Future<void> append(Map<String, Object?> line) {
    final text = jsonEncode(line);
    final next = _queue.then((_) => _write(text)).catchError((Object _) {});
    _queue = next;
    return next;
  }

  Future<void> clear() async {
    if (await file.exists()) await file.delete();
    if (await rolledFile.exists()) await rolledFile.delete();
  }

  Future<void> _write(String line) async {
    await _rollIfNeeded();
    await file.writeAsString('$line\n', mode: FileMode.append, flush: true);
  }

  Future<void> _rollIfNeeded() async {
    if (!await file.exists()) return;
    if (await file.length() <= maxBytes) return;
    if (await rolledFile.exists()) await rolledFile.delete();
    await file.rename(rolledFile.path);
  }
}

/// 打开默认落点；拿不到可用目录时返回 null（调用方当作「只记页面」处理）。
///
/// 优先外部私有目录（`Android/data/<包名>/files/diag`），adb 能直接 pull；
/// 取不到再退回内部目录。
Future<CaptureDiagLogFile?> openCaptureDiagLog() async {
  try {
    Directory? base;
    try {
      base = await getExternalStorageDirectory();
    } on Object {
      base = null;
    }
    base ??= await getApplicationSupportDirectory();
    final directory = Directory('${base.path}${Platform.pathSeparator}diag');
    await directory.create(recursive: true);
    return CaptureDiagLogFile(directory);
  } on Object {
    return null;
  }
}
