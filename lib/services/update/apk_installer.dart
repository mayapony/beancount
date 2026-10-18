import 'package:flutter/services.dart';

import 'update_models.dart';

/// Kotlin `preflight` 的结果。
class ApkPreflight {
  const ApkPreflight({
    required this.ok,
    required this.reason,
    this.apkVersionCode,
    this.currentVersionCode,
    this.apkVersionName,
  });

  final bool ok;

  /// `ok` / `parse` / `downgrade` / `signature` / `versionName` / `noInstaller`
  final String reason;

  final int? apkVersionCode;
  final int? currentVersionCode;
  final String? apkVersionName;

  factory ApkPreflight.fromMap(Map<String, dynamic> map) => ApkPreflight(
        ok: map['ok'] == true,
        reason: map['reason'] is String ? map['reason'] as String : 'parse',
        apkVersionCode: (map['apkVersionCode'] as num?)?.toInt(),
        currentVersionCode: (map['currentVersionCode'] as num?)?.toInt(),
        apkVersionName:
            map['apkVersionName'] is String ? map['apkVersionName'] as String : null,
      );
}

/// 安装器平台能力；测试用 Fake 实现。
abstract class ApkInstaller {
  Future<bool> canInstall();

  Future<void> openInstallSettings();

  Future<ApkPreflight> preflight(
    String path, {
    required String expectedVersion,
  });

  Future<void> install(String path);
}

class MethodChannelApkInstaller implements ApkInstaller {
  MethodChannelApkInstaller({MethodChannel? channel})
      : _channel = channel ??
            const MethodChannel('com.jindou.bean_count/update');

  static const channelName = 'com.jindou.bean_count/update';

  final MethodChannel _channel;

  @override
  Future<bool> canInstall() async {
    final value = await _channel.invokeMethod<bool>('canInstall');
    return value ?? false;
  }

  @override
  Future<void> openInstallSettings() =>
      _channel.invokeMethod<void>('openInstallSettings');

  @override
  Future<ApkPreflight> preflight(
    String path, {
    required String expectedVersion,
  }) async {
    final map = await _channel.invokeMapMethod<String, dynamic>(
      'preflight',
      {'path': path, 'expectedVersion': expectedVersion},
    );
    if (map == null) {
      throw const UpdateFailure(
        UpdateFailureKind.parse,
        '安装包预检没有返回结果',
      );
    }
    return ApkPreflight.fromMap(map);
  }

  @override
  Future<void> install(String path) async {
    try {
      await _channel.invokeMethod<void>('install', {'path': path});
    } on PlatformException catch (error) {
      throw installFailureFromPlatform(error);
    }
  }
}

UpdateFailure installFailureFromPlatform(PlatformException error) {
  final kind = switch (error.code) {
    'permission' => UpdateFailureKind.permission,
    'no_installer' => UpdateFailureKind.noInstaller,
    'invalid_path' => UpdateFailureKind.parse,
    'install_failed' => UpdateFailureKind.parse,
    _ => UpdateFailureKind.unknown,
  };
  return UpdateFailure(kind, error.message ?? '安装失败，请重试');
}
