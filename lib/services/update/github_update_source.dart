import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:http/http.dart' as http;

import 'app_version.dart';
import 'update_models.dart';
import 'update_url_policy.dart';
import 'version_compare.dart';

/// 更新源：返回最新稳定发布，或 304 表示没有变化。
abstract class UpdateSource {
  Future<CheckOutcome> fetchLatest({String? etag});

  void close();
}

const String _repository = 'mayapony/beancount';
const String _apiVersion = '2022-11-28';

/// GitHub Releases 实现。仓库必须公开；私有仓库的未鉴权请求会得到 404。
class GitHubUpdateSource implements UpdateSource {
  GitHubUpdateSource({
    required AppVersion current,
    http.Client? client,
    Uri? apiBase,
    this.timeout = const Duration(seconds: 10),
    bool? allowInsecure,
  })  : _current = current,
        _client = client ?? http.Client(),
        _ownsClient = client == null,
        _apiBase = apiBase ?? _defaultApiBase {
    _allowInsecure = allowInsecure ??
        (kDebugMode && _apiBase.host != UpdateUrlPolicy.github.apiBase.host);
    _policy = UpdateUrlPolicy(
      apiBase: _apiBase,
      allowInsecure: _allowInsecure,
    );
  }

  final AppVersion _current;
  final http.Client _client;
  final bool _ownsClient;
  final Uri _apiBase;
  final Duration timeout;

  late final bool _allowInsecure;
  late final UpdateUrlPolicy _policy;

  static Uri get _defaultApiBase {
    const raw = String.fromEnvironment('UPDATE_API_BASE');
    if (raw.isEmpty) return Uri.parse('https://api.github.com');
    final trimmed = raw.endsWith('/')
        ? raw.substring(0, raw.length - 1)
        : raw;
    return Uri.parse(trimmed);
  }

  Uri get _latestUri {
    final basePath = _apiBase.path.endsWith('/')
        ? _apiBase.path.substring(0, _apiBase.path.length - 1)
        : _apiBase.path;
    return _apiBase.replace(
      path: '$basePath/repos/$_repository/releases/latest',
    );
  }

  String get _userAgent => 'BeanCount/${_current.normalized ?? 'unknown'}';

  Map<String, String> _headers({String? etag}) => {
        'Accept': 'application/vnd.github+json',
        'X-GitHub-Api-Version': _apiVersion,
        'User-Agent': _userAgent,
        if (etag != null && etag.isNotEmpty) 'If-None-Match': etag,
      };

  @override
  Future<CheckOutcome> fetchLatest({String? etag}) async {
    final http.Response response;
    try {
      response = await _client
          .get(_latestUri, headers: _headers(etag: etag))
          .timeout(timeout);
    } on TimeoutException {
      throw const UpdateFailure(
        UpdateFailureKind.timeout,
        '检查更新超时，稍后再试',
      );
    } on http.ClientException {
      throw const UpdateFailure(
        UpdateFailureKind.network,
        '网络不通，检查一下连接',
      );
    }

    final responseEtag = response.headers['etag'];

    if (response.statusCode == 304) {
      return CheckOutcome.notModified(etag: responseEtag ?? etag);
    }
    if (response.statusCode == 404) {
      throw const UpdateFailure(
        UpdateFailureKind.notFound,
        '更新源不可用（仓库可能不是公开的）',
        statusCode: 404,
      );
    }
    if (response.statusCode == 403 || response.statusCode == 429) {
      final remaining = response.headers['x-ratelimit-remaining'];
      if (response.statusCode == 429 || remaining == '0') {
        throw const UpdateFailure(
          UpdateFailureKind.rateLimited,
          '检查太频繁，稍后再试',
          statusCode: 403,
        );
      }
      throw UpdateFailure(
        UpdateFailureKind.unknown,
        '更新服务拒绝请求（${response.statusCode}）',
        statusCode: response.statusCode,
      );
    }
    if (response.statusCode >= 500) {
      throw UpdateFailure(
        UpdateFailureKind.server,
        'GitHub 暂时不可用',
        statusCode: response.statusCode,
      );
    }
    if (response.statusCode != 200) {
      throw UpdateFailure(
        UpdateFailureKind.unknown,
        '更新服务返回 ${response.statusCode}',
        statusCode: response.statusCode,
      );
    }

    return _parse(response, etag: responseEtag ?? etag);
  }

  Future<CheckOutcome> _parse(
    http.Response response, {
    String? etag,
  }) async {
    Object? decoded;
    try {
      decoded = jsonDecode(utf8.decode(response.bodyBytes, allowMalformed: true));
    } on FormatException {
      throw const UpdateFailure(
        UpdateFailureKind.malformed,
        '更新信息无法解析',
      );
    }
    if (decoded is! Map<String, dynamic>) {
      throw const UpdateFailure(
        UpdateFailureKind.malformed,
        '更新信息无法解析',
      );
    }

    final tag = decoded['tag_name'];
    final version = tag is String ? normalizeVersion(tag) : null;
    if (version == null) {
      throw const UpdateFailure(
        UpdateFailureKind.malformed,
        '更新信息缺少有效版本号',
      );
    }

    final rawAssets = decoded['assets'];
    if (rawAssets is! List) {
      throw const UpdateFailure(
        UpdateFailureKind.malformed,
        '更新信息缺少附件列表',
      );
    }
    final assets = rawAssets
        .whereType<Map>()
        .map((item) => item.cast<String, dynamic>())
        .toList(growable: false);

    final apk = _findApk(assets);
    if (apk == null) {
      throw const UpdateFailure(
        UpdateFailureKind.noApk,
        '发布里没有安装包',
      );
    }

    final rawUrl = apk['browser_download_url'];
    final apkUrl = rawUrl is String ? Uri.tryParse(rawUrl) : null;
    if (apkUrl == null || !_policy.allowsApk(apkUrl)) {
      throw const UpdateFailure(
        UpdateFailureKind.unknown,
        '更新源返回了非预期的下载地址',
      );
    }

    final rawSize = apk['size'];
    final sizeBytes = rawSize is int ? rawSize : 0;
    final notes = decoded['body'] is String ? decoded['body'] as String : '';
    final rawPublished = decoded['published_at'];
    final publishedAt =
        rawPublished is String ? DateTime.tryParse(rawPublished) : null;

    final sha256 = _digestOf(apk) ?? await _fetchChecksum(assets);

    return CheckOutcome(
      etag: etag,
      release: UpdateRelease(
        version: version,
        tag: tag as String,
        notes: notes,
        apkUrl: apkUrl,
        sizeBytes: sizeBytes,
        sha256: sha256,
        publishedAt: publishedAt,
        assetName: apk['name'] is String ? apk['name'] as String : null,
      ),
    );
  }

  Map<String, dynamic>? _findApk(List<Map<String, dynamic>> assets) {
    Map<String, dynamic>? firstApk;
    for (final asset in assets) {
      final name = asset['name'];
      if (name is! String) continue;
      if (name == 'app-release.apk') return asset;
      if (firstApk == null && name.toLowerCase().endsWith('.apk')) {
        firstApk = asset;
      }
    }
    return firstApk;
  }

  String? _digestOf(Map<String, dynamic> asset) {
    final digest = asset['digest'];
    if (digest is! String || !digest.startsWith('sha256:')) return null;
    final hex = digest.substring('sha256:'.length).toLowerCase();
    return RegExp(r'^[0-9a-f]{64}$').hasMatch(hex) ? hex : null;
  }

  Future<String?> _fetchChecksum(List<Map<String, dynamic>> assets) async {
    Map<String, dynamic>? sums;
    for (final asset in assets) {
      if (asset['name'] == 'SHA256SUMS.txt') {
        sums = asset;
        break;
      }
    }
    if (sums == null) return null;

    final rawUrl = sums['browser_download_url'];
    final url = rawUrl is String ? Uri.tryParse(rawUrl) : null;
    if (url == null || !_policy.allowsChecksum(url)) return null;

    try {
      final response = await _client.get(url, headers: {
        'Accept': 'application/octet-stream',
        'User-Agent': _userAgent,
      }).timeout(timeout);
      if (response.statusCode != 200) return null;
      final text = utf8.decode(response.bodyBytes, allowMalformed: true);
      for (final line in const LineSplitter().convert(text)) {
        if (!line.contains('app-release.apk')) continue;
        final match = RegExp(r'^([0-9a-fA-F]{64})\s+').firstMatch(line.trim());
        if (match != null) return match.group(1)!.toLowerCase();
      }
    } catch (_) {
      // 校验和拉取失败时返回 null，由控制器按「无校验和」拒绝安装。
    }
    return null;
  }

  @override
  void close() {
    if (_ownsClient) _client.close();
  }
}
