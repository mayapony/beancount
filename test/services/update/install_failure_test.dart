import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bean_count/services/update/apk_installer.dart';
import 'package:bean_count/services/update/install_failure.dart';
import 'package:bean_count/services/update/update_models.dart';

void main() {
  test('preflight 的每种 reason 映射为对应失败类型', () {
    const cases = {
      'downgrade': UpdateFailureKind.downgrade,
      'signature': UpdateFailureKind.signature,
      'versionName': UpdateFailureKind.versionName,
      'parse': UpdateFailureKind.parse,
      'noInstaller': UpdateFailureKind.noInstaller,
    };

    for (final entry in cases.entries) {
      final failure = failureForPreflight(
        ApkPreflight(ok: false, reason: entry.key),
      );
      expect(failure.kind, entry.value, reason: entry.key);
    }
  });

  test('平台 permission 错误映射为权限失败', () {
    final failure = installFailureFromPlatform(
      PlatformException(code: 'permission', message: '需要允许安装未知应用'),
    );

    expect(failure.kind, UpdateFailureKind.permission);
  });

  test('签名不一致文案要求先导出，不引导直接卸载', () {
    final message = installFailureMessage(UpdateFailureKind.signature);

    expect(message, contains('先导出'));
    expect(message, contains('签名不一致'));
  });

  test('未知 reason 回落到通用失败，而不是假装成功', () {
    final failure = failureForPreflight(
      const ApkPreflight(ok: false, reason: 'somethingNew'),
    );

    expect(failure.kind, UpdateFailureKind.unknown);
    expect(failure.message, isNotEmpty);
  });

  test('ApkPreflight 解析空字段', () {
    final preflight = ApkPreflight.fromMap(const {'ok': true, 'reason': 'ok'});

    expect(preflight.ok, isTrue);
    expect(preflight.apkVersionCode, isNull);
    expect(preflight.currentVersionCode, isNull);
    expect(preflight.apkVersionName, isNull);
  });
}
