import 'dart:async';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:bean_count/services/update/apk_downloader.dart';
import 'package:bean_count/services/update/apk_downloader_io.dart';
import 'package:bean_count/services/update/app_version.dart';
import 'package:bean_count/services/update/update_cache.dart';
import 'package:bean_count/services/update/update_models.dart';
import 'package:bean_count/services/update/update_url_policy.dart';

const _apkUrl =
    'https://github.com/mayapony/beancount/releases/download/v1.0.2/app-release.apk';
final _bytes = List<int>.generate(1024, (i) => i % 251);
final _sha = sha256.convert(_bytes).toString();

UpdateRelease _release({String? sha, String url = _apkUrl, int size = 1024}) {
  return UpdateRelease(
    version: '1.0.2',
    tag: 'v1.0.2',
    notes: '',
    apkUrl: Uri.parse(url),
    sizeBytes: size,
    sha256: sha ?? _sha,
  );
}

void main() {
  late Directory temp;
  late UpdateCache cache;

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('bean_update_download_');
    cache = UpdateCache(root: () async => temp);
  });

  tearDown(() async {
    if (await temp.exists()) await temp.delete(recursive: true);
  });

  HttpApkDownloader downloader(http.Client client) => HttpApkDownloader(
        current: const AppVersion(version: '1.0.1', buildNumber: '2'),
        client: client,
        cache: cache,
        urlPolicy: UpdateUrlPolicy.github,
      );

  test('流式下载并校验成功，落到 cache/update/app-release.apk', () async {
    final progress = <int>[];
    final client = MockClient(
      (_) async => http.Response.bytes(_bytes, 200),
    );

    final path = await downloader(client).download(
      _release(),
      onProgress: (received, total) => progress.add(received),
    );

    expect(path, endsWith(UpdateCache.apkName));
    expect(await File(path).readAsBytes(), _bytes);
    expect(progress.last, _bytes.length);
    expect(await File('$path.part').exists(), isFalse);
  });

  test('SHA-256 不匹配时删除文件并拒绝安装', () async {
    final client = MockClient((_) async => http.Response.bytes(_bytes, 200));

    await expectLater(
      downloader(client).download(_release(sha: 'c' * 64)),
      throwsA(isA<UpdateFailure>()
          .having((e) => e.kind, 'kind', UpdateFailureKind.checksum)),
    );

    final dir = await cache.directory();
    expect(await dir.list().isEmpty, isTrue);
  });

  test('发布没有 SHA-256 时直接拒绝，不发请求', () async {
    var requested = false;
    final client = MockClient((_) async {
      requested = true;
      return http.Response.bytes(_bytes, 200);
    });

    await expectLater(
      downloader(client).download(_release(sha: '')),
      throwsA(isA<UpdateFailure>()
          .having((e) => e.kind, 'kind', UpdateFailureKind.noChecksum)),
    );
    expect(requested, isFalse);
  });

  test('非 GitHub 下载地址被拒绝', () async {
    final client = MockClient((_) async => http.Response.bytes(_bytes, 200));

    await expectLater(
      downloader(client).download(_release(url: 'https://evil.example/app.apk')),
      throwsA(isA<UpdateFailure>()
          .having((e) => e.message, 'message', contains('不在允许的 GitHub 域名下'))),
    );
  });

  test('HTTP 404 / 5xx 映射为可读失败', () async {
    await expectLater(
      downloader(MockClient((_) async => http.Response('', 404)))
          .download(_release()),
      throwsA(isA<UpdateFailure>()
          .having((e) => e.kind, 'kind', UpdateFailureKind.notFound)),
    );
    await expectLater(
      downloader(MockClient((_) async => http.Response('', 503)))
          .download(_release()),
      throwsA(isA<UpdateFailure>()
          .having((e) => e.kind, 'kind', UpdateFailureKind.server)),
    );
  });

  test('缓存目录不可写时映射为 io', () async {
    await File('${temp.path}/${UpdateCache.directoryName}').writeAsString('x');

    await expectLater(
      downloader(MockClient((_) async => http.Response.bytes(_bytes, 200)))
          .download(_release()),
      throwsA(isA<UpdateFailure>()
          .having((e) => e.kind, 'kind', UpdateFailureKind.io)),
    );
  });

  test('取消下载后不留下 .part 或目标文件', () async {
    final controller = StreamController<List<int>>();
    final client = MockClient.streaming((request, bodyStream) async {
      return http.StreamedResponse(controller.stream, 200, contentLength: 8);
    });
    final token = CancelToken();

    final future = downloader(client).download(_release(), cancelToken: token);
    await Future<void>.delayed(const Duration(milliseconds: 10));
    token.cancel();
    controller.add([1, 2, 3, 4]);
    await controller.close();

    await expectLater(
      future,
      throwsA(isA<UpdateFailure>()
          .having((e) => e.kind, 'kind', UpdateFailureKind.cancelled)),
    );

    final dir = await cache.directory();
    expect(await dir.list().isEmpty, isTrue);
  });

  test('流空闲超时映射为 timeout 并清理', () async {
    final controller = StreamController<List<int>>();
    final client = MockClient.streaming((request, bodyStream) async {
      return http.StreamedResponse(controller.stream, 200, contentLength: 8);
    });

    final future = HttpApkDownloader(
      current: const AppVersion(version: '1.0.1', buildNumber: '2'),
      client: client,
      cache: cache,
      urlPolicy: UpdateUrlPolicy.github,
      inactivityTimeout: const Duration(milliseconds: 20),
    ).download(_release());

    await expectLater(
      future,
      throwsA(isA<UpdateFailure>()
          .having((e) => e.kind, 'kind', UpdateFailureKind.timeout)),
    );
    await controller.close();
    final dir = await cache.directory();
    expect(await dir.list().isEmpty, isTrue);
  });
}
