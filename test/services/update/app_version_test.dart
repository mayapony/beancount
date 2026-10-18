import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';

import 'package:bean_count/services/update/app_version.dart';

PackageInfo _info({String version = '1.0.1', String buildNumber = '2'}) =>
    PackageInfo(
      appName: '金豆',
      packageName: 'com.jindou.bean_count',
      version: version,
      buildNumber: buildNumber,
    );

void main() {
  group('AppVersion', () {
    test('从 PackageInfo 读取 version 与 buildNumber', () {
      final version = AppVersion.fromPackageInfo(_info());

      expect(version.version, '1.0.1');
      expect(version.buildNumber, '2');
      expect(version.isKnown, isTrue);
      expect(version.label, 'v1.0.1');
      expect(version.fullLabel, 'v1.0.1 (2)');
    });

    test('version 自带 v 前缀时不重复', () {
      final version = AppVersion.fromPackageInfo(_info(version: 'v1.2.3'));

      expect(version.normalized, '1.2.3');
      expect(version.label, 'v1.2.3');
    });

    test('读不到版本时展示「版本未知」', () {
      expect(AppVersion.unknown.isKnown, isFalse);
      expect(AppVersion.unknown.label, '版本未知');
      expect(AppVersion.unknown.fullLabel, '版本未知');
    });

    test('buildNumber 为空时 fullLabel 不追加括号', () {
      const version = AppVersion(version: '1.0.1', buildNumber: '');

      expect(version.label, 'v1.0.1');
      expect(version.fullLabel, 'v1.0.1');
    });

    test('loadAppVersion 正常返回注入的包信息', () async {
      final version = await loadAppVersion(loader: () async => _info());

      expect(version, const AppVersion(version: '1.0.1', buildNumber: '2'));
    });

    test('loadAppVersion 读取失败回落 unknown，不抛出', () async {
      final version = await loadAppVersion(
        loader: () async => throw StateError('platform channel unavailable'),
      );

      expect(version, AppVersion.unknown);
    });
  });
}
