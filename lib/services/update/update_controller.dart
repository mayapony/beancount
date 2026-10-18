import 'package:flutter/foundation.dart';

import 'apk_downloader.dart';
import 'apk_installer.dart';
import 'app_version.dart';
import 'github_update_source.dart';
import 'install_failure.dart';
import 'update_models.dart';
import 'update_preferences.dart';
import 'version_compare.dart';

enum UpdatePhase {
  idle,
  checking,
  upToDate,
  available,
  downloading,
  ready,
  installing,
  failed,
}

/// 应用内更新的唯一状态机。UI 只读它、调它，不自己发请求或碰文件。
class UpdateController extends ChangeNotifier {
  UpdateController({
    required AppVersion current,
    required UpdateSource source,
    required UpdatePreferences preferences,
    required ApkDownloader downloader,
    required ApkInstaller installer,
    DateTime Function()? now,
    Future<AppVersion> Function()? versionLoader,
  })  : _current = current,
        _source = source,
        _preferences = preferences,
        _downloader = downloader,
        _installer = installer,
        _now = now ?? DateTime.now,
        _versionLoader = versionLoader ?? loadAppVersion;

  AppVersion _current;
  final UpdateSource _source;
  final UpdatePreferences _preferences;
  final ApkDownloader _downloader;
  final ApkInstaller _installer;
  final DateTime Function() _now;
  final Future<AppVersion> Function() _versionLoader;

  UpdatePhase _phase = UpdatePhase.idle;
  UpdateRelease? _release;
  String? _downloadPath;
  int? _receivedBytes;
  int? _totalBytes;
  UpdateFailure? _failure;
  bool _autoCheck = true;
  DateTime? _lastCheckedAt;
  String? _updatedTo;
  bool _initialized = false;
  bool _checking = false;
  CancelToken? _cancelToken;
  String? _installingVersion;

  UpdatePhase get phase => _phase;
  UpdateRelease? get release => _release;
  String? get downloadPath => _downloadPath;
  int? get receivedBytes => _receivedBytes;
  int? get totalBytes => _totalBytes;
  double? get progress {
    final total = _totalBytes;
    if (total == null || total <= 0) return null;
    return (_receivedBytes ?? 0) / total;
  }

  UpdateFailure? get failure => _failure;
  bool get autoCheckEnabled => _autoCheck;
  DateTime? get lastCheckedAt => _lastCheckedAt;
  AppVersion get current => _current;
  String? get updatedTo => _updatedTo;

  bool get isBusy =>
      _phase == UpdatePhase.checking ||
      _phase == UpdatePhase.downloading ||
      _phase == UpdatePhase.installing;

  /// 启动时读取偏好、处理上次安装结果并清理缓存；可重复调用。
  Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;
    _autoCheck = await _preferences.autoCheckEnabled();
    _lastCheckedAt = await _preferences.lastCheckedAt();

    final pending = await _preferences.pendingVersion();
    if (pending != null && pending.isNotEmpty) {
      if (pending == _current.normalized) {
        _updatedTo = pending;
      }
      await _preferences.setPendingVersion(null);
    }

    try {
      await _downloader.cleanup();
    } catch (_) {
      // 清理失败不影响启动。
    }
    notifyListeners();
  }

  Future<bool> autoCheckDue() async {
    await initialize();
    if (!_autoCheck) return false;
    return _preferences.shouldAutoCheck(_now());
  }

  /// 自动检查：未到点、关闭、失败或已跳过时返回 null，调用方不用弹任何东西。
  Future<UpdateRelease?> autoCheck() async {
    await initialize();
    if (!_autoCheck) return null;
    if (!await _preferences.shouldAutoCheck(_now())) return null;
    return _check(manual: false);
  }

  /// 手动检查：忽略节流与跳过；结果通过 phase/failure 暴露。
  Future<UpdateRelease?> checkManually() async {
    await initialize();
    return _check(manual: true);
  }

  Future<UpdateRelease?> _check({required bool manual}) async {
    if (_checking ||
        _phase == UpdatePhase.downloading ||
        _phase == UpdatePhase.installing) {
      return null;
    }
    _checking = true;
    _phase = UpdatePhase.checking;
    _failure = null;
    notifyListeners();

    try {
      // 手动检查是用户显式要一个结论：不用 ETag 缓存，避免旧缓存让
      // 服务端回 304（响应里没有版本号）而误报「已是最新」。
      final cachedEtag = manual ? null : await _preferences.etag();
      final outcome = await _source.fetchLatest(etag: cachedEtag);
      final checkedAt = _now();
      await _preferences.markChecked(checkedAt);
      _lastCheckedAt = checkedAt;

      if (outcome.notModified) {
        // 304 只说明「最新发布没变」，不代表当前版本就是最新的：
        // 本次会话已发现的更高版本仍然有效，不能因为 304 就报「已是最新」。
        final known = _release;
        if (known != null && _isNewerThanCurrent(known.version)) {
          await _preferences.setEtag(null);
          _phase = UpdatePhase.available;
          notifyListeners();
          return known;
        }
        await _preferences.setEtag(outcome.etag);
        _phase = UpdatePhase.upToDate;
        notifyListeners();
        return null;
      }

      final release = outcome.release;
      if (release == null) {
        throw const UpdateFailure(
          UpdateFailureKind.malformed,
          '更新信息无法解析',
        );
      }
      _release = release;

      if (!_isNewerThanCurrent(release.version)) {
        // 已是最新：这时 ETag 才有意义，下次 304 可以继续判成「已是最新」。
        await _preferences.setEtag(outcome.etag);
        _phase = UpdatePhase.upToDate;
        notifyListeners();
        return null;
      }

      // 还有没装的更高版本时不缓存 ETag：否则下次请求走 304，响应里没有
      // 版本号，会把「有新版本」误判成「已是最新」。
      await _preferences.setEtag(null);

      if (!manual && !await _preferences.shouldPrompt(release.version, _now())) {
        _phase = UpdatePhase.upToDate;
        notifyListeners();
        return null;
      }

      _phase = UpdatePhase.available;
      notifyListeners();
      return release;
    } on UpdateFailure catch (error) {
      _failure = error;
      _phase = UpdatePhase.failed;
      notifyListeners();
      return null;
    } catch (_) {
      _failure = const UpdateFailure(
        UpdateFailureKind.unknown,
        '检查更新失败，请稍后再试',
      );
      _phase = UpdatePhase.failed;
      notifyListeners();
      return null;
    } finally {
      _checking = false;
    }
  }

  bool _isNewerThanCurrent(String version) {
    final currentVersion = _current.normalized;
    return currentVersion != null && isNewerVersion(version, currentVersion);
  }

  Future<void> setAutoCheck(bool enabled) async {
    await initialize();
    _autoCheck = enabled;
    await _preferences.setAutoCheckEnabled(enabled);
    notifyListeners();
  }

  Future<void> dismiss() async {
    final release = _release;
    if (release == null) return;
    await _preferences.dismiss(release.version, _now());
    _phase = UpdatePhase.idle;
    notifyListeners();
  }

  Future<void> skipVersion() async {
    final release = _release;
    if (release == null) return;
    await _preferences.skipVersion(release.version);
    _phase = UpdatePhase.idle;
    notifyListeners();
  }

  Future<void> download() async {
    final release = _release;
    if (release == null ||
        _phase == UpdatePhase.downloading ||
        _phase == UpdatePhase.installing) {
      return;
    }
    final token = CancelToken();
    _cancelToken = token;
    _phase = UpdatePhase.downloading;
    _failure = null;
    _receivedBytes = 0;
    _totalBytes = release.sizeBytes > 0 ? release.sizeBytes : null;
    notifyListeners();

    try {
      final path = await _downloader.download(
        release,
        cancelToken: token,
        onProgress: (received, total) {
          _receivedBytes = received;
          _totalBytes = total ?? _totalBytes;
          notifyListeners();
        },
      );
      _downloadPath = path;
      _phase = UpdatePhase.ready;
      notifyListeners();
    } on UpdateFailure catch (error) {
      if (error.kind == UpdateFailureKind.cancelled) {
        if (_phase == UpdatePhase.downloading) {
          _phase = UpdatePhase.available;
        }
      } else {
        _failure = error;
        _phase = UpdatePhase.failed;
      }
      notifyListeners();
    } catch (_) {
      _failure = const UpdateFailure(
        UpdateFailureKind.unknown,
        '下载失败，请重试',
      );
      _phase = UpdatePhase.failed;
      notifyListeners();
    } finally {
      _cancelToken = null;
    }
  }

  void cancelDownload() {
    _cancelToken?.cancel();
    if (_phase == UpdatePhase.downloading) {
      _phase = UpdatePhase.available;
      _receivedBytes = 0;
      _totalBytes = null;
      notifyListeners();
    }
  }

  Future<void> install() async {
    final release = _release;
    final path = _downloadPath;
    if (release == null || path == null || _phase == UpdatePhase.installing) {
      return;
    }

    try {
      if (!await _installer.canInstall()) {
        _failure = const UpdateFailure(
          UpdateFailureKind.permission,
          '需要允许金豆安装未知应用',
        );
        _phase = UpdatePhase.failed;
        notifyListeners();
        return;
      }

      final preflight = await _installer.preflight(
        path,
        expectedVersion: release.version,
      );
      if (!preflight.ok) {
        _failure = failureForPreflight(preflight);
        _phase = UpdatePhase.failed;
        notifyListeners();
        return;
      }

      _installingVersion = release.version;
      await _preferences.setPendingVersion(release.version);
      await _installer.install(path);
      _phase = UpdatePhase.installing;
      notifyListeners();
    } on UpdateFailure catch (error) {
      _failure = error;
      _phase = UpdatePhase.failed;
      notifyListeners();
    } catch (_) {
      _failure = const UpdateFailure(
        UpdateFailureKind.unknown,
        '安装失败，请重试',
      );
      _phase = UpdatePhase.failed;
      notifyListeners();
    }
  }

  Future<void> openInstallSettings() => _installer.openInstallSettings();

  /// 从系统安装器返回后调用：版本变了才算成功，否则不假装更新成功。
  Future<void> onAppResumed() async {
    if (_phase != UpdatePhase.installing) return;
    final target = _installingVersion ?? _release?.version;
    if (target == null) return;

    final next = await _versionLoader();
    if (next.normalized == target) {
      _current = next;
      _updatedTo = target;
      _phase = UpdatePhase.upToDate;
      _release = null;
      _downloadPath = null;
      _installingVersion = null;
      await _preferences.setPendingVersion(null);
      try {
        await _downloader.cleanup();
      } catch (_) {
        // 清理失败不影响结果。
      }
    } else {
      _failure = const UpdateFailure(
        UpdateFailureKind.unknown,
        '安装未完成，请重试',
      );
      _phase = UpdatePhase.failed;
    }
    notifyListeners();
  }

  /// Shell 取一次就清掉，避免每次重建都提示。
  String? takeUpdatedTo() {
    final value = _updatedTo;
    _updatedTo = null;
    return value;
  }

  @override
  void dispose() {
    _source.close();
    _downloader.close();
    super.dispose();
  }
}
