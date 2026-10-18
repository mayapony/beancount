import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:bean_count/services/update/update_cache.dart';

void main() {
  late Directory temp;
  late UpdateCache cache;
  final now = DateTime(2026, 10, 18, 12);

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('bean_update_cache_');
    cache = UpdateCache(root: () async => temp, now: () => now);
  });

  tearDown(() async {
    if (await temp.exists()) await temp.delete(recursive: true);
  });

  Future<File> file(String name, {required Duration age}) async {
    final dir = await cache.directory();
    final result = File('${dir.path}/$name');
    await result.writeAsBytes([1, 2, 3]);
    await result.setLastModified(now.subtract(age));
    return result;
  }

  test('删除过期 APK 与孤儿 .part，保留新鲜文件', () async {
    final oldApk = await file('app-release.apk', age: const Duration(days: 8));
    final freshApk = await file('other.apk', age: const Duration(hours: 2));
    final oldPart = await file(
      'app-release.apk.part',
      age: const Duration(days: 2),
    );
    final freshPart = await file(
      'active.apk.part',
      age: const Duration(minutes: 1),
    );

    await cache.clean();

    expect(await oldApk.exists(), isFalse);
    expect(await freshApk.exists(), isTrue);
    expect(await oldPart.exists(), isFalse);
    expect(await freshPart.exists(), isTrue);
  });

  test('目录不存在时创建 update 目录', () async {
    final dir = await cache.directory();

    expect(await dir.exists(), isTrue);
    expect(dir.path, endsWith(UpdateCache.directoryName));
  });
}
