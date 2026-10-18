import 'update_models.dart';

/// 下载取消令牌；取消后下载器删除 `.part` 并抛 `cancelled`。
class CancelToken {
  bool _cancelled = false;

  bool get isCancelled => _cancelled;

  void cancel() => _cancelled = true;

  void throwIfCancelled() {
    if (_cancelled) {
      throw const UpdateFailure(UpdateFailureKind.cancelled, '已取消下载');
    }
  }
}

typedef DownloadProgress = void Function(int received, int? total);

/// APK 下载器。返回本地路径；校验失败必须抛异常且不留下可安装文件。
abstract class ApkDownloader {
  Future<String> download(
    UpdateRelease release, {
    DownloadProgress? onProgress,
    CancelToken? cancelToken,
  });

  /// 启动时清理过期缓存。
  Future<void> cleanup();

  void close();
}
