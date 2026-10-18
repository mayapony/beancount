import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:bean_count/services/update/app_version.dart';
import 'package:bean_count/services/update/github_update_source.dart';
import 'package:bean_count/services/update/update_models.dart';

const _current = AppVersion(version: '1.0.1', buildNumber: '2');
const _apkUrl =
    'https://github.com/mayapony/beancount/releases/download/v1.0.2/app-release.apk';
const _sumsUrl =
    'https://github.com/mayapony/beancount/releases/download/v1.0.2/SHA256SUMS.txt';
final _digest = 'a' * 64;
final _sumsDigest = 'b' * 64;

Map<String, dynamic> _releaseJson({
  String tag = 'v1.0.2',
  String? digest = 'sha256:PLACEHOLDER',
  bool includeApk = true,
  bool includeSums = false,
  String apkUrl = _apkUrl,
}) {
  return {
    'tag_name': tag,
    'body': '安装说明\n\n## 变更\n\n- feat(update): 应用内更新\n- docs: 文档',
    'published_at': '2026-10-18T03:00:00Z',
    'assets': [
      if (includeApk)
        {
          'name': 'app-release.apk',
          'size': 47914601,
          'browser_download_url': apkUrl,
          if (digest != null)
            'digest': digest == 'sha256:PLACEHOLDER'
                ? 'sha256:$_digest'
                : digest,
        },
      if (includeSums)
        {
          'name': 'SHA256SUMS.txt',
          'browser_download_url': _sumsUrl,
        },
    ],
  };
}

http.Response _json(Map<String, dynamic> body, {int status = 200, Map<String, String>? headers}) =>
    http.Response(
      jsonEncode(body),
      status,
      headers: {'content-type': 'application/json', ...?headers},
    );

String? _header(http.BaseRequest request, String name) {
  for (final entry in request.headers.entries) {
    if (entry.key.toLowerCase() == name.toLowerCase()) return entry.value;
  }
  return null;
}

GitHubUpdateSource _source(
  MockClient client, {
  Duration timeout = const Duration(seconds: 10),
}) {
  return GitHubUpdateSource(
    current: _current,
    client: client,
    apiBase: Uri.parse('https://api.github.com'),
    timeout: timeout,
    allowInsecure: false,
  );
}

void main() {
  group('GitHubUpdateSource', () {
    test('200 解析版本、说明、大小、SHA-256 与下载地址', () async {
      late http.BaseRequest captured;
      final client = MockClient((request) async {
        captured = request;
        return _json(_releaseJson());
      });

      final outcome = await _source(client).fetchLatest(etag: 'W/"old"');

      expect(outcome.notModified, isFalse);
      expect(outcome.release?.version, '1.0.2');
      expect(outcome.release?.tag, 'v1.0.2');
      expect(outcome.release?.sizeBytes, 47914601);
      expect(outcome.release?.sha256, _digest);
      expect(outcome.release?.apkUrl, Uri.parse(_apkUrl));
      expect(outcome.release?.notes, contains('应用内更新'));
      expect(_header(captured, 'User-Agent'), 'BeanCount/1.0.1');
      expect(_header(captured, 'Accept'), 'application/vnd.github+json');
      expect(_header(captured, 'If-None-Match'), 'W/"old"');
    });

    test('304 表示没有变化，并保留 ETag', () async {
      final client = MockClient((request) async {
        expect(_header(request, 'if-none-match'), 'W/"etag"');
        return http.Response('', 304, headers: {'etag': 'W/"etag"'});
      });

      final outcome = await _source(client).fetchLatest(etag: 'W/"etag"');

      expect(outcome.notModified, isTrue);
      expect(outcome.release, isNull);
      expect(outcome.etag, 'W/"etag"');
    });

    test('404 映射为更新源不可用', () async {
      final client = MockClient((_) async => http.Response('Not Found', 404));

      await expectLater(
        _source(client).fetchLatest(),
        throwsA(isA<UpdateFailure>()
            .having((e) => e.kind, 'kind', UpdateFailureKind.notFound)
            .having((e) => e.message, 'message', contains('更新源不可用'))),
      );
    });

    test('403 且配额耗尽映射为限流', () async {
      final client = MockClient((_) async => http.Response(
            'rate limited',
            403,
            headers: {'x-ratelimit-remaining': '0'},
          ));

      await expectLater(
        _source(client).fetchLatest(),
        throwsA(isA<UpdateFailure>()
            .having((e) => e.kind, 'kind', UpdateFailureKind.rateLimited)),
      );
    });

    test('5xx 映射为 GitHub 暂时不可用', () async {
      final client = MockClient((_) async => http.Response('oops', 502));

      await expectLater(
        _source(client).fetchLatest(),
        throwsA(isA<UpdateFailure>()
            .having((e) => e.kind, 'kind', UpdateFailureKind.server)),
      );
    });

    test('畸形 JSON 映射为无法解析', () async {
      final client = MockClient((_) async => http.Response('not json', 200));

      await expectLater(
        _source(client).fetchLatest(),
        throwsA(isA<UpdateFailure>()
            .having((e) => e.kind, 'kind', UpdateFailureKind.malformed)),
      );
    });

    test('缺 APK 附件映射为没有安装包', () async {
      final client = MockClient(
        (_) async => _json(_releaseJson(includeApk: false)),
      );

      await expectLater(
        _source(client).fetchLatest(),
        throwsA(isA<UpdateFailure>()
            .having((e) => e.kind, 'kind', UpdateFailureKind.noApk)),
      );
    });

    test('digest 缺失时回退读取 SHA256SUMS.txt', () async {
      final client = MockClient((request) async {
        if (request.url.path.endsWith('SHA256SUMS.txt')) {
          return http.Response('$_sumsDigest  app-release.apk\n', 200);
        }
        return _json(_releaseJson(digest: null, includeSums: true));
      });

      final outcome = await _source(client).fetchLatest();

      expect(outcome.release?.sha256, _sumsDigest);
    });

    test('非 GitHub 下载地址被拒绝', () async {
      final client = MockClient(
        (_) async => _json(_releaseJson(apkUrl: 'https://evil.example/app.apk')),
      );

      await expectLater(
        _source(client).fetchLatest(),
        throwsA(isA<UpdateFailure>()
            .having((e) => e.message, 'message', contains('非预期的下载地址'))),
      );
    });

    test('超时映射为 timeout', () async {
      final client = MockClient((_) async {
        await Future<void>.delayed(const Duration(milliseconds: 100));
        return _json(_releaseJson());
      });

      await expectLater(
        _source(client, timeout: const Duration(milliseconds: 1)).fetchLatest(),
        throwsA(isA<UpdateFailure>()
            .having((e) => e.kind, 'kind', UpdateFailureKind.timeout)),
      );
    });
  });
}
