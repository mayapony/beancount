import '../../data/repositories/app_state_repository.dart';

/// 「以后再说」的记录。
class DismissedUpdate {
  const DismissedUpdate({required this.version, required this.at});

  final String version;
  final DateTime at;
}

/// 更新偏好的持久化：全部存在 `app_state`，不新增表、不做数据库迁移。
class UpdatePreferences {
  UpdatePreferences(this._state);

  static const kAutoCheck = 'update_auto_check';
  static const kLastCheckedAt = 'update_last_check_at';
  static const kEtag = 'update_etag';
  static const kSkippedVersion = 'update_skipped_version';
  static const kDismissedVersion = 'update_dismissed_version';
  static const kDismissedAt = 'update_dismissed_at';
  static const kPendingVersion = 'update_pending_version';

  static const autoCheckInterval = Duration(hours: 24);
  static const dismissInterval = Duration(hours: 24);

  final AppStateRepository _state;

  Future<bool> autoCheckEnabled() async =>
      (await _state.read(kAutoCheck)) != 'false';

  Future<void> setAutoCheckEnabled(bool enabled) =>
      _state.write(kAutoCheck, enabled ? 'true' : 'false');

  Future<DateTime?> lastCheckedAt() async =>
      _parseDateTime(await _state.read(kLastCheckedAt));

  Future<void> markChecked(DateTime at) =>
      _state.write(kLastCheckedAt, at.toUtc().toIso8601String());

  Future<String?> etag() => _state.read(kEtag);

  Future<void> setEtag(String? etag) async {
    if (etag == null || etag.isEmpty) {
      await _state.remove(kEtag);
    } else {
      await _state.write(kEtag, etag);
    }
  }

  Future<String?> skippedVersion() => _state.read(kSkippedVersion);

  Future<void> skipVersion(String version) =>
      _state.write(kSkippedVersion, version);

  Future<void> clearSkippedVersion() => _state.remove(kSkippedVersion);

  Future<DismissedUpdate?> dismissed() async {
    final version = await _state.read(kDismissedVersion);
    final at = _parseDateTime(await _state.read(kDismissedAt));
    if (version == null || version.isEmpty || at == null) return null;
    return DismissedUpdate(version: version, at: at);
  }

  Future<void> dismiss(String version, DateTime at) async {
    await _state.write(kDismissedVersion, version);
    await _state.write(kDismissedAt, at.toUtc().toIso8601String());
  }

  Future<String?> pendingVersion() => _state.read(kPendingVersion);

  Future<void> setPendingVersion(String? version) async {
    if (version == null || version.isEmpty) {
      await _state.remove(kPendingVersion);
    } else {
      await _state.write(kPendingVersion, version);
    }
  }

  /// 自动检查是否到点：开关打开 + 距上次成功检查 ≥24h（或从未检查）。
  Future<bool> shouldAutoCheck(DateTime now) async {
    if (!await autoCheckEnabled()) return false;
    final last = await lastCheckedAt();
    if (last == null) return true;
    return now.toUtc().difference(last.toUtc()) >= autoCheckInterval;
  }

  /// 自动提示是否该出现：跳过的版本不再提示；同一版本「以后再说」24h 内不提示。
  Future<bool> shouldPrompt(String version, DateTime now) async {
    if (await skippedVersion() == version) return false;
    final dismissed = await this.dismissed();
    if (dismissed == null || dismissed.version != version) return true;
    return now.toUtc().difference(dismissed.at.toUtc()) >= dismissInterval;
  }

  static DateTime? _parseDateTime(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    return DateTime.tryParse(raw);
  }
}
