library;

import '../../data/repositories/app_state_repository.dart';

/// 自动记账（无障碍 + 通知）的偏好：总开关 + 失效心跳。
///
/// 默认关闭；只有显式开启并完成系统授权后才采集。开关落在 `app_state`，
/// 与截屏自动记账（`ScreenshotSettings`）分开，两个能力独立启停。
class CaptureSettings {
  const CaptureSettings({this.enabled = false, this.lastCaptureAt});

  final bool enabled;

  /// 最近一次成功捕获到支付的时间；用于「连续 7 天零捕获」的失效提示。
  final DateTime? lastCaptureAt;

  CaptureSettings copyWith({bool? enabled, DateTime? lastCaptureAt}) {
    return CaptureSettings(
      enabled: enabled ?? this.enabled,
      lastCaptureAt: lastCaptureAt ?? this.lastCaptureAt,
    );
  }
}

/// 读写 [CaptureSettings]；坏值按关闭处理，避免开着一个读不懂的开关。
class CaptureSettingsStore {
  CaptureSettingsStore(this._state);

  final AppStateRepository _state;

  static const kEnabledKey = 'capture_enabled';
  static const kLastCaptureAtKey = 'capture_last_capture_at';

  Future<CaptureSettings> load() async {
    return CaptureSettings(
      enabled: (await _state.read(kEnabledKey)) == 'true',
      lastCaptureAt: DateTime.tryParse(await _state.read(kLastCaptureAtKey) ?? ''),
    );
  }

  Future<void> save(CaptureSettings settings) async {
    await _state.write(kEnabledKey, settings.enabled ? 'true' : 'false');
    await _state.remove(kLastCaptureAtKey);
    final at = settings.lastCaptureAt;
    if (at != null) {
      await _state.write(kLastCaptureAtKey, at.toUtc().toIso8601String());
    }
  }

  Future<void> setEnabled(bool enabled) async {
    final current = await load();
    await save(current.copyWith(enabled: enabled));
  }

  /// 记录一次成功捕获：把心跳时间推进到现在。
  Future<void> markCaptured(DateTime at) async {
    final current = await load();
    await save(current.copyWith(lastCaptureAt: at));
  }
}

/// 失效判定阈值：开启后连续这么久没捕获到支付，就提示「可能已失效」。
const captureStaleAfter = Duration(days: 7);

/// 是否应提示「自动记账可能已失效」。
///
/// 未开启、或从未捕获过（用户刚打开还没发生支付）都不提示；只有「已开启 +
/// 距上次捕获超过 [captureStaleAfter]」才提示，捕获恢复后（时间推进）自动消失。
bool isCaptureStale({
  required bool enabled,
  DateTime? lastCaptureAt,
  DateTime? now,
}) {
  if (!enabled || lastCaptureAt == null) return false;
  return (now ?? DateTime.now()).difference(lastCaptureAt) > captureStaleAfter;
}
