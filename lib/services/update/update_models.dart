/// 检查更新与下载安装共用的模型。
library;

/// 一次检查成功后的发布信息。
class UpdateRelease {
  const UpdateRelease({
    required this.version,
    required this.tag,
    required this.notes,
    required this.apkUrl,
    required this.sizeBytes,
    required this.sha256,
    this.publishedAt,
    this.assetName,
  });

  /// 规范化后的 versionName，例如 `1.0.2`（一定没有 `v`）。
  final String version;

  /// 原始 tag，例如 `v1.0.2`。
  final String tag;

  /// GitHub Release 的正文；可能为空。
  final String notes;

  final Uri apkUrl;
  final int sizeBytes;

  /// APK 的 SHA-256（小写 hex）；缺失时为 null，控制器会拒绝安装。
  final String? sha256;

  final DateTime? publishedAt;
  final String? assetName;

  String get sizeLabel => formatBytes(sizeBytes);
}

/// 检查结果：304 时 `notModified` 为 true；200 时 `release` 一定非空。
class CheckOutcome {
  const CheckOutcome({this.release, this.etag, this.notModified = false});

  const CheckOutcome.notModified({this.etag})
      : release = null,
        notModified = true;

  final UpdateRelease? release;
  final String? etag;
  final bool notModified;
}

/// 更新链路失败的类型；UI 用它决定提示与按钮。
enum UpdateFailureKind {
  network,
  timeout,
  rateLimited,
  notFound,
  server,
  malformed,
  noApk,
  noChecksum,
  cancelled,
  io,
  checksum,
  permission,
  downgrade,
  signature,
  versionName,
  parse,
  noInstaller,
  unknown,
}

class UpdateFailure implements Exception {
  const UpdateFailure(this.kind, this.message, {this.statusCode});

  final UpdateFailureKind kind;
  final String message;
  final int? statusCode;

  @override
  String toString() => message;
}

/// 人类可读的体积；使用十进制 MB，和 GitHub Release 页展示一致。
String formatBytes(int bytes) {
  if (bytes <= 0) return '未知大小';
  const mb = 1000 * 1000;
  const kb = 1000;
  if (bytes >= mb) return '${(bytes / mb).toStringAsFixed(1)} MB';
  if (bytes >= kb) return '${(bytes / kb).toStringAsFixed(0)} KB';
  return '$bytes B';
}
