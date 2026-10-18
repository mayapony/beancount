import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bean_count/services/update/apk_installer.dart';
import 'package:bean_count/services/update/update_models.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel(MethodChannelApkInstaller.channelName);
  late MethodChannelApkInstaller installer;
  late List<MethodCall> calls;

  setUp(() {
    calls = [];
    installer = MethodChannelApkInstaller();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      switch (call.method) {
        case 'canInstall':
          return true;
        case 'openInstallSettings':
          return null;
        case 'preflight':
          return {
            'ok': true,
            'reason': 'ok',
            'apkVersionCode': 200,
            'currentVersionCode': 143,
            'apkVersionName': '1.0.2',
          };
        case 'install':
          return null;
        default:
          return null;
      }
    });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('canInstall 读取平台布尔值', () async {
    expect(await installer.canInstall(), isTrue);
    expect(calls.single.method, 'canInstall');
  });

  test('openInstallSettings 调用对应方法', () async {
    await installer.openInstallSettings();

    expect(calls.single.method, 'openInstallSettings');
  });

  test('preflight 传路径与期望版本，并解析返回', () async {
    final result = await installer.preflight(
      '/data/user/0/com.jindou.bean_count/cache/update/app-release.apk',
      expectedVersion: '1.0.2',
    );

    expect(calls.single.method, 'preflight');
    expect(calls.single.arguments, {
      'path': '/data/user/0/com.jindou.bean_count/cache/update/app-release.apk',
      'expectedVersion': '1.0.2',
    });
    expect(result.ok, isTrue);
    expect(result.reason, 'ok');
    expect(result.apkVersionCode, 200);
    expect(result.currentVersionCode, 143);
    expect(result.apkVersionName, '1.0.2');
  });

  test('install 传本地路径', () async {
    await installer.install('/cache/update/app-release.apk');

    expect(calls.single.method, 'install');
    expect(calls.single.arguments, {'path': '/cache/update/app-release.apk'});
  });

  test('平台拒绝安装时映射为 UpdateFailure', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      throw PlatformException(code: 'permission', message: '需要允许安装未知应用');
    });

    await expectLater(
      installer.install('/cache/update/app-release.apk'),
      throwsA(isA<UpdateFailure>()
          .having((e) => e.kind, 'kind', UpdateFailureKind.permission)
          .having((e) => e.message, 'message', contains('未知应用'))),
    );
  });
}
