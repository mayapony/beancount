import 'package:flutter_test/flutter_test.dart';

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

class _FakeSource implements UpdateSource {
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

class _FakeDownloader implements ApkDownloader {
  String path = '/tmp/update/app-release.apk';
  UpdateFailure? error;
  int calls = 0;
  bool cleaned = false;

  @override
  Future<String> download(
    UpdateRelease release, {
    DownloadProgress? onProgress,
    CancelToken? cancelToken,
  }) async {
    calls++;
    onProgress?.call(10, 100);
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

class _FakeInstaller implements ApkInstaller {
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

UpdateRelease _release({String version = '1.0.2'}) => UpdateRelease(
      version: version,
      tag: 'v$version',
      notes: '## 变更\n- feat: 应用内更新',
      apkUrl: Uri.parse(
        'https://github.com/mayapony/beancount/releases/download/v$version/app-release.apk',
      ),
      sizeBytes: 100,
      sha256: 'a' * 64,
    );

void main() {
  late AppDatabase db;
  late UpdatePreferences prefs;
  late _FakeSource source;
  late _FakeDownloader downloader;
  late _FakeInstaller installer;
  final now = DateTime.utc(2026, 10, 18, 12);

  setUp(() async {
    db = AppDatabase(openInMemoryConnection());
    prefs = UpdatePreferences(AppStateRepository(db));
    await db.select(db.appState).get();
    source = _FakeSource();
    downloader = _FakeDownloader();
    installer = _FakeInstaller();
  });

  tearDown(() async => db.close());

  UpdateController make({
    AppVersion current = const AppVersion(version: '1.0.1', buildNumber: '143'),
    Future<AppVersion> Function()? versionLoader,
  }) {
    final controller = UpdateController(
      current: current,
      source: source,
      preferences: prefs,
      downloader: downloader,
      installer: installer,
      now: () => now,
      versionLoader: versionLoader,
    );
    addTearDown(controller.dispose);
    return controller;
  }

  Future<UpdateController> withUpdate() async {
    source.outcome = CheckOutcome(release: _release());
    final controller = make();
    await controller.checkManually();
    return controller;
  }

  test('24 小时内自动检查不联网', () async {
    await prefs.markChecked(now.subtract(const Duration(hours: 12)));
    source.outcome = CheckOutcome(release: _release());

    final controller = make();
    expect(await controller.autoCheck(), isNull);
    expect(source.calls, 0);
  });

  test('自动检查发现新版本并进入 available', () async {
    source.outcome = CheckOutcome(release: _release());

    final controller = make();
    final release = await controller.autoCheck();

    expect(release?.version, '1.0.2');
    expect(controller.phase, UpdatePhase.available);
  });

  test('跳过版本后自动检查不提示，手动检查仍能看到', () async {
    await prefs.skipVersion('1.0.2');
    source.outcome = CheckOutcome(release: _release());

    final controller = make();
    expect(await controller.autoCheck(), isNull);
    expect(controller.phase, UpdatePhase.upToDate);

    final manual = await controller.checkManually();
    expect(manual?.version, '1.0.2');
    expect(controller.phase, UpdatePhase.available);
  });

  test('304 与同版本都进入 upToDate', () async {
    source.outcome = const CheckOutcome.notModified(etag: 'W/"e"');
    final controller = make();
    await controller.checkManually();
    expect(controller.phase, UpdatePhase.upToDate);

    source.outcome = CheckOutcome(release: _release(version: '1.0.1'));
    await controller.checkManually();
    expect(controller.phase, UpdatePhase.upToDate);
  });

  test('自动检查失败保持 failed 状态但不抛异常', () async {
    source.error = const UpdateFailure(
      UpdateFailureKind.timeout,
      '检查更新超时，稍后再试',
    );

    final controller = make();
    expect(await controller.autoCheck(), isNull);
    expect(controller.phase, UpdatePhase.failed);
    expect(controller.failure?.kind, UpdateFailureKind.timeout);
  });

  test('下载成功显示进度并进入 ready', () async {
    final controller = await withUpdate();
    await controller.download();

    expect(controller.phase, UpdatePhase.ready);
    expect(controller.downloadPath, downloader.path);
    expect(controller.progress, 1.0);
    expect(downloader.calls, 1);
  });

  test('下载校验失败进入 failed，不暴露可安装路径', () async {
    downloader.error = const UpdateFailure(
      UpdateFailureKind.checksum,
      '安装包校验失败，已删除',
    );
    final controller = await withUpdate();
    await controller.download();

    expect(controller.phase, UpdatePhase.failed);
    expect(controller.failure?.kind, UpdateFailureKind.checksum);
    expect(controller.downloadPath, isNull);
  });

  test('没有安装未知应用权限时不调用系统安装器', () async {
    installer.canInstallValue = false;
    final controller = await withUpdate();
    await controller.download();
    await controller.install();

    expect(controller.phase, UpdatePhase.failed);
    expect(controller.failure?.kind, UpdateFailureKind.permission);
    expect(installer.installCalls, 0);
  });

  test('签名不一致时阻止安装，提示先导出', () async {
    installer.preflightResult =
        const ApkPreflight(ok: false, reason: 'signature');
    final controller = await withUpdate();
    await controller.download();
    await controller.install();

    expect(controller.phase, UpdatePhase.failed);
    expect(controller.failure?.kind, UpdateFailureKind.signature);
    expect(controller.failure?.message, contains('先导出'));
    expect(installer.installCalls, 0);
  });

  test('安装成功后进入 installing 并记录待安装版本', () async {
    final controller = await withUpdate();
    await controller.download();
    await controller.install();

    expect(controller.phase, UpdatePhase.installing);
    expect(installer.installCalls, 1);
    expect(await prefs.pendingVersion(), '1.0.2');
  });

  test('安装返回后版本变大才算成功，并清理缓存与 pending', () async {
    final controller = make(
      versionLoader: () async =>
          const AppVersion(version: '1.0.2', buildNumber: '200'),
    );
    source.outcome = CheckOutcome(release: _release());
    await controller.checkManually();
    await controller.download();
    await controller.install();
    await controller.onAppResumed();

    expect(controller.phase, UpdatePhase.upToDate);
    expect(controller.updatedTo, '1.0.2');
    expect(controller.takeUpdatedTo(), '1.0.2');
    expect(controller.takeUpdatedTo(), isNull);
    expect(await prefs.pendingVersion(), isNull);
    expect(downloader.cleaned, isTrue);
  });

  test('安装被取消时版本没变，不提示更新成功', () async {
    final controller = make(
      versionLoader: () async =>
          const AppVersion(version: '1.0.1', buildNumber: '143'),
    );
    source.outcome = CheckOutcome(release: _release());
    await controller.checkManually();
    await controller.download();
    await controller.install();
    await controller.onAppResumed();

    expect(controller.phase, UpdatePhase.failed);
    expect(controller.updatedTo, isNull);
    expect(controller.failure?.message, contains('安装未完成'));
  });

  test('启动时读到与当前版本相等的 pending，提示已更新并清理', () async {
    await prefs.setPendingVersion('1.0.2');
    final controller = make(
      current: const AppVersion(version: '1.0.2', buildNumber: '200'),
    );

    await controller.initialize();

    expect(controller.updatedTo, '1.0.2');
    expect(await prefs.pendingVersion(), isNull);
    expect(downloader.cleaned, isTrue);
  });
}
