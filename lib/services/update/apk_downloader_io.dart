import 'dart:async';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;

import 'apk_downloader.dart';
import 'app_version.dart';
import 'update_cache.dart';
import 'update_models.dart';
import 'update_url_policy.dart';

/// 用 `http` 流式下载 APK 到缓存，边下边报进度，完成后校验 SHA-256。
class HttpApkDownloader implements ApkDownloader {
  HttpApkDownloader({
    required AppVersion current,
    http.Client? client,
    UpdateCache? cache,
    UpdateUrlPolicy? urlPolicy,
    this.connectTimeout = const Duration(seconds: 15),
    this.inactivityTimeout = const Duration(seconds: 30),
  })  : _current = current,
        _client = client ?? http.Client(),
        _ownsClient = client == null,
        _cache = cache ?? UpdateCache(),
        _policy = urlPolicy ?? UpdateUrlPolicy.github;

  final AppVersion _current;
  final http.Client _client;
  final bool _ownsClient;
  final UpdateCache _cache;
  final UpdateUrlPolicy _policy;
  final Duration connectTimeout;
  final Duration inactivityTimeout;

  String get _userAgent => 'BeanCount/${_current.normalized ?? 'unknown'}';

  @override
  Future<String> download(
    UpdateRelease release, {
    DownloadProgress? onProgress,
    CancelToken? cancelToken,
  }) async {
    final expected = release.sha256;
    if (expected == null || expected.isEmpty) {
      throw const UpdateFailure(
        UpdateFailureKind.noChecksum,
        '发布没有提供校验和，已拒绝安装',
      );
    }
    if (!_policy.allowsApk(release.apkUrl)) {
      throw const UpdateFailure(
        UpdateFailureKind.unknown,
        '下载地址不在允许的 GitHub 域名下',
      );
    }

    final Directory dir;
    try {
      dir = await _cache.directory();
    } on FileSystemException {
      throw const UpdateFailure(
        UpdateFailureKind.io,
        '存储空间不足或无法写入缓存',
      );
    }
    final target = File('${dir.path}/${UpdateCache.apkName}');
    final part = File('${target.path}${UpdateCache.partSuffix}');
    if (await part.exists()) await part.delete();

    IOSink? sink;
    var completed = false;
    try {
      final request = http.Request('GET', release.apkUrl)
        ..headers['User-Agent'] = _userAgent;
      final response =
          await _client.send(request).timeout(connectTimeout);

      if (response.statusCode == 404) {
        throw const UpdateFailure(
          UpdateFailureKind.notFound,
          '安装包已下架，请打开 Release 页',
          statusCode: 404,
        );
      }
      if (response.statusCode >= 500) {
        throw UpdateFailure(
          UpdateFailureKind.server,
          'GitHub 暂时不可用，请稍后重试',
          statusCode: response.statusCode,
        );
      }
      if (response.statusCode != 200) {
        throw UpdateFailure(
          UpdateFailureKind.network,
          '下载失败（${response.statusCode}），请重试',
          statusCode: response.statusCode,
        );
      }

      final total = response.contentLength;
      var received = 0;
      sink = part.openWrite();
      await for (final chunk in response.stream.timeout(inactivityTimeout)) {
        cancelToken?.throwIfCancelled();
        sink.add(chunk);
        received += chunk.length;
        onProgress?.call(received, total);
      }
      await sink.flush();
      await sink.close();
      sink = null;

      cancelToken?.throwIfCancelled();

      final actual = await _sha256(part);
      if (actual != expected.toLowerCase()) {
        throw const UpdateFailure(
          UpdateFailureKind.checksum,
          '安装包校验失败，已删除',
        );
      }

      if (await target.exists()) await target.delete();
      await part.rename(target.path);
      completed = true;
      return target.path;
    } on UpdateFailure {
      rethrow;
    } on TimeoutException {
      throw const UpdateFailure(
        UpdateFailureKind.timeout,
        '下载超时，请重试',
      );
    } on http.ClientException {
      throw const UpdateFailure(
        UpdateFailureKind.network,
        '下载失败，请检查网络',
      );
    } on FileSystemException {
      throw const UpdateFailure(
        UpdateFailureKind.io,
        '存储空间不足或无法写入缓存',
      );
    } finally {
      if (sink != null) {
        try {
          await sink.close();
        } on FileSystemException {
          // 失败路径上关闭 sink 的异常不再覆盖原始错误。
        }
      }
      if (!completed && await part.exists()) {
        try {
          await part.delete();
        } on FileSystemException {
          // 清理失败留给下次启动的 UpdateCache.clean。
        }
      }
    }
  }

  Future<String> _sha256(File file) async {
    final digest = await sha256.bind(file.openRead()).first;
    return digest.toString();
  }

  @override
  Future<void> cleanup() => _cache.clean();

  @override
  void close() {
    if (_ownsClient) _client.close();
  }
}
