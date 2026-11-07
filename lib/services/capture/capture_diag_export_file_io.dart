import 'dart:io';

import 'capture_diag_log.dart';

/// 把导出的诊断报告写进 `diag/export-<时间戳>.txt`，返回路径。
///
/// 写文件是为了 adb 取证：页面上的分享要先解锁手机点一遍，`adb pull` 不用。
/// 拿不到目录或写失败时返回 null，调用方只提示「未保存」。
Future<String?> writeCaptureDiagExport(String text, {DateTime? at}) async {
  try {
    final log = await openCaptureDiagLog();
    if (log == null) return null;
    final stamp = (at ?? DateTime.now())
        .toIso8601String()
        .replaceAll(RegExp(r'[:.]'), '-');
    final file = File(
      '${log.directory.path}${Platform.pathSeparator}export-$stamp.txt',
    );
    await file.writeAsString(text, flush: true);
    return file.path;
  } on Object {
    return null;
  }
}
