import 'dart:async';

import 'package:bean_count/data/db/app_database.dart';
import 'package:bean_count/data/db/connection.dart';
import 'package:bean_count/data/repositories/app_state_repository.dart';
import 'package:bean_count/services/update/apk_downloader.dart';
import 'package:bean_count/services/update/apk_installer.dart';
import 'package:bean_count/services/update/app_version.dart';
import 'package:bean_count/services/update/github_update_source.dart';
import 'package:bean_count/services/update/update_controller.dart';
import 'package:bean_count/services/update/update_models.dart';
import 'package:bean_count/services/update/update_preferences.dart';

const testCurrentVersion =
    AppVersion(version: '1.0.1', buildNumber: '143');

UpdateRelease testRelease({String version = '1.0.2'}) => UpdateRelease(
      version: version,
      tag: 'v$version',
      notes: '安装说明\n\n## 变更\n\n'
          '- feat(update): 应用内检查更新\n'
          '- fix(android): 修复 release 联网\n'
          '- docs: 更新手册\n'
          '- perf(download): 减少读取\n',
      apkUrl: Uri.parse(
        'https://github.com/mayapony/beancount/releases/download/v$version/app-release.apk',
      ),
      sizeBytes: 47914601,
      sha256: 'a' * 64,
    );

class FakeUpdateSource implements UpdateSource {
  CheckOutcome outcome = const CheckOutcome();
  UpdateFailure? error;
  int calls = 0;
  String? lastEtag;

  @override
  Future<CheckOutcome> fetchLatest({String? etag}) async {
    calls++;
    lastEtag = etag;
    if (error != null) throw error!;
    return outcome;
  }

  @override
  void close() {}
}

class FakeApkDownloader implements ApkDownloader {
  String path = '/tmp/update/app-release.apk';
  UpdateFailure? error;
  int calls = 0;
  bool cleaned = false;
  CancelToken? lastToken;
  Completer<String>? hold;

  @override
  Future<String> download(
    UpdateRelease release, {
    DownloadProgress? onProgress,
    CancelToken? cancelToken,
  }) async {
    calls++;
    lastToken = cancelToken;
    onProgress?.call(10, 100);
    if (hold != null) return hold!.future;
    onProgress?.call(100, 100);
    if (error != null) throw error!;
    return path;
  }

  @override
  Future<void> cleanup() async {
    cleaned = true;
  }

  @override
  void close() {}
}

class FakeApkInstaller implements ApkInstaller {
  bool canInstallValue = true;
  ApkPreflight preflightResult =
      const ApkPreflight(ok: true, reason: 'ok');
  UpdateFailure? installError;
  int preflightCalls = 0;
  int installCalls = 0;
  bool openedSettings = false;

  @override
  Future<bool> canInstall() async => canInstallValue;

  @override
  Future<void> openInstallSettings() async {
    openedSettings = true;
  }

  @override
  Future<ApkPreflight> preflight(
    String path, {
    required String expectedVersion,
  }) async {
    preflightCalls++;
    return preflightResult;
  }

  @override
  Future<void> install(String path) async {
    installCalls++;
    if (installError != null) throw installError!;
  }
}

/// 页面测试用：内存库 + 假 source/downloader/installer + 固定时钟。
class UpdateTestContext {
  UpdateTestContext._({
    required this.db,
    required this.preferences,
    required this.source,
    required this.downloader,
    required this.installer,
    required this.controller,
    required this.now,
  });

  final AppDatabase db;
  final UpdatePreferences preferences;
  final FakeUpdateSource source;
  final FakeApkDownloader downloader;
  final FakeApkInstaller installer;
  final UpdateController controller;
  final DateTime now;

  static Future<UpdateTestContext> create({
    AppVersion current = testCurrentVersion,
    Future<AppVersion> Function()? versionLoader,
    String? pendingVersion,
  }) async {
    final db = AppDatabase(openInMemoryConnection());
    final preferences = UpdatePreferences(AppStateRepository(db));
    await db.select(db.appState).get();
    if (pendingVersion != null) {
      await preferences.setPendingVersion(pendingVersion);
    }
    final source = FakeUpdateSource();
    final downloader = FakeApkDownloader();
    final installer = FakeApkInstaller();
    final now = DateTime.utc(2026, 10, 18, 12);
    final controller = UpdateController(
      current: current,
      source: source,
      preferences: preferences,
      downloader: downloader,
      installer: installer,
      now: () => now,
      versionLoader: versionLoader,
    );
    await controller.initialize();
    return UpdateTestContext._(
      db: db,
      preferences: preferences,
      source: source,
      downloader: downloader,
      installer: installer,
      controller: controller,
      now: now,
    );
  }

  Future<void> makeAvailable({UpdateRelease? release}) async {
    source.outcome = CheckOutcome(release: release ?? testRelease());
    await controller.checkManually();
  }

  Future<void> close() async {
    controller.dispose();
    await db.close();
  }
}
