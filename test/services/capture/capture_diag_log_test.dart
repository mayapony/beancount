import 'dart:convert';
import 'dart:io';

import 'package:bean_count/services/capture/capture_diag_log.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory dir;
  late CaptureDiagLogFile log;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('bean_diag_');
    log = CaptureDiagLogFile(dir, maxBytes: 300);
  });

  tearDown(() async {
    if (await dir.exists()) await dir.delete(recursive: true);
  });

  test('追加的行是独立 JSON，可按行解析', () async {
    await log.append({'seq': 1, 'kind': 'no_rule'});
    await log.append({'seq': 2, 'kind': 'entry_written'});

    final lines = await log.file.readAsLines();
    expect(lines, hasLength(2));
    expect(jsonDecode(lines.first)['kind'], 'no_rule');
    expect(jsonDecode(lines.last)['kind'], 'entry_written');
  });

  test('超过上限滚动成 .1，新文件从头写', () async {
    for (var i = 0; i < 40; i++) {
      await log.append({'seq': i, 'padding': 'x' * 40});
    }

    expect(await log.rolledFile.exists(), isTrue);
    expect(await log.file.length(), lessThanOrEqualTo(300 + 100));
    expect(await log.rolledFile.length(), greaterThan(0));
  });

  test('滚动只保留一份旧文件', () async {
    for (var i = 0; i < 200; i++) {
      await log.append({'seq': i, 'padding': 'x' * 40});
    }

    final names = dir.listSync().map((e) => e.path.split(Platform.pathSeparator).last);
    expect(names.where((n) => n.startsWith('events.log')).toSet(),
        {'events.log', 'events.log.1'});
  });

  test('并发追加不会写出半行', () async {
    await Future.wait([
      for (var i = 0; i < 20; i++) log.append({'seq': i}),
    ]);

    final lines = await log.file.readAsLines();
    expect(lines, hasLength(20));
    for (final line in lines) {
      expect(() => jsonDecode(line), returnsNormally);
    }
  });

  test('clear 删掉当前与滚动文件', () async {
    for (var i = 0; i < 40; i++) {
      await log.append({'seq': i, 'padding': 'x' * 40});
    }
    await log.clear();

    expect(await log.file.exists(), isFalse);
    expect(await log.rolledFile.exists(), isFalse);
  });
}
