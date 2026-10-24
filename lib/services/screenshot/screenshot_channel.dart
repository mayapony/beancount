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
      return await _channel
              .invokeMethod<bool>('setEnabled', {'enabled': enabled}) ??
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
      final result =
          await _channel.invokeMapMethod<String, bool>('hasPermissions');
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

  /// 上一次「取回失败截图」是否没取到图（取一次就清零）。
  ///
  /// 点「读取截图失败」通知时，原生侧会把那张图重新读出来当作分享图交过来；
  /// 如果连这时都读不到（图片被删/权限被撤），这里返回 true，让界面说一句原因。
  Future<bool> takeSharedImageError() async {
    if (!isSupported) return false;
    try {
      return await _channel.invokeMethod<bool>('takeSharedImageError') ?? false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  /// 原生主动通知：前台收到分享 / 用户点结果通知要求消费待确认队列。
  /// MethodChannel 只能挂一个 handler，所以两个事件放在一个监听里。
  void setNativeListeners({
    Future<void> Function()? onSharedImage,
    Future<void> Function()? onPendingAvailable,
  }) {
    if (!isSupported) return;
    _channel.setMethodCallHandler((call) async {
      switch (call.method) {
        case 'sharedImageAvailable':
          await onSharedImage?.call();
        case 'pendingAvailable':
          await onPendingAvailable?.call();
      }
      return null;
    });
  }
}
