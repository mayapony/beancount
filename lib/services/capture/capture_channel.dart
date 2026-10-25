import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// 自动记账需要的原生能力（Android 实现见 `CapturePlugin.kt`）。
///
/// 非 Android / Web 上 [isSupported] 为 false，调用方据此不渲染入口、不调用方法，
/// 也不报错——这是「Android-only 门」。
abstract class CapturePlatform {
  bool get isSupported;

  /// 启停后台捕获服务（headless 引擎），并持久化原生开关（开机恢复用）。
  Future<bool> setEnabled(bool enabled);

  Future<bool> isAccessibilityEnabled();

  Future<bool> isNotificationListenerEnabled();

  Future<void> openAccessibilitySettings();

  Future<void> openNotificationListenerSettings();

  /// 取走「点已记账通知要打开自动记账列表」的挂起标记（取一次就清空）。
  Future<bool> takeOpenAutoEntries();

  /// 原生主动通知：用户点了已记账通知，要求打开「最近自动记账」列表。
  void setNativeListeners({Future<void> Function()? onOpenAutoEntries});
}

/// Dart 侧的自动记账通道；非 Android 上所有方法都安全返回默认值。
class CaptureChannel implements CapturePlatform {
  const CaptureChannel();

  static const _channel = MethodChannel('com.jindou.bean_count/capture');

  @override
  bool get isSupported =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  @override
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

  @override
  Future<bool> isAccessibilityEnabled() async {
    if (!isSupported) return false;
    try {
      return await _channel.invokeMethod<bool>('isAccessibilityEnabled') ?? false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  @override
  Future<bool> isNotificationListenerEnabled() async {
    if (!isSupported) return false;
    try {
      return await _channel.invokeMethod<bool>('isNotificationListenerEnabled') ??
          false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  @override
  Future<void> openAccessibilitySettings() async {
    if (!isSupported) return;
    try {
      await _channel.invokeMethod<void>('openAccessibilitySettings');
    } on PlatformException {
      // 拉起系统设置失败不打断用户
    } on MissingPluginException {
      // 忽略
    }
  }

  @override
  Future<void> openNotificationListenerSettings() async {
    if (!isSupported) return;
    try {
      await _channel.invokeMethod<void>('openNotificationListenerSettings');
    } on PlatformException {
      // 同上
    } on MissingPluginException {
      // 忽略
    }
  }

  @override
  Future<bool> takeOpenAutoEntries() async {
    if (!isSupported) return false;
    try {
      return await _channel.invokeMethod<bool>('takeOpenAutoEntries') ?? false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  @override
  void setNativeListeners({Future<void> Function()? onOpenAutoEntries}) {
    if (!isSupported) return;
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'openAutoEntries') {
        await onOpenAutoEntries?.call();
      }
      return null;
    });
  }
}
