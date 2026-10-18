import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Dart 侧的截图能力入口（Android 原生实现见 `ScreenshotPlugin.kt`）。
///
/// 非 Android / Web 上所有方法都安全地返回「不支持」，调用方不用分支。
class ScreenshotChannel {
  const ScreenshotChannel();

  static const _channel = MethodChannel('com.jindou.bean_count/screenshot');

  bool get isSupported =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  Future<bool> setEnabled(bool enabled) async {
    if (!isSupported) return false;
    try {
      return await _channel.invokeMethod<bool>('setEnabled', {'enabled': enabled}) ??
          false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  Future<bool> requestPermissions() async {
    if (!isSupported) return false;
    try {
      return await _channel.invokeMethod<bool>('requestPermissions') ?? false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  Future<bool> hasMediaPermission() async {
    if (!isSupported) return false;
    try {
      final result = await _channel.invokeMapMethod<String, bool>('hasPermissions');
      return result?['media'] ?? false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  /// 取走系统分享面板发来的图片路径（取一次就清空）。
  Future<String?> takeSharedImagePath() async {
    if (!isSupported) return null;
    try {
      return await _channel.invokeMethod<String>('takeSharedImagePath');
    } on PlatformException {
      return null;
    } on MissingPluginException {
      return null;
    }
  }

  /// 前台收到分享时原生会主动通知，避免用户已经打开 App 时没反应。
  void setSharedImageListener(Future<void> Function() listener) {
    if (!isSupported) return;
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'sharedImageAvailable') {
        await listener();
      }
      return null;
    });
  }
}
