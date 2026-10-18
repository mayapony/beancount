import 'dart:io';

import 'package:flutter/foundation.dart' show kDebugMode;

import '../../data/repositories/app_state_repository.dart';
import 'apk_downloader_io.dart';
import 'apk_installer.dart';
import 'app_version.dart';
import 'github_update_source.dart';
import 'update_controller.dart';
import 'update_preferences.dart';
import 'update_url_policy.dart';

/// Android：组装真实更新链路。Web/iOS 走 stub，不创建 controller。
UpdateController? createUpdateController({
  required AppStateRepository appState,
  required AppVersion version,
  DateTime Function()? now,
}) {
  if (!Platform.isAndroid) return null;

  const rawBase = String.fromEnvironment('UPDATE_API_BASE');
  final customBase = rawBase.isEmpty ? null : Uri.parse(rawBase);
  final apiBase = customBase ?? UpdateUrlPolicy.github.apiBase;
  final allowInsecure = kDebugMode && customBase != null;
  final policy = UpdateUrlPolicy(
    apiBase: apiBase,
    allowInsecure: allowInsecure,
  );

  return UpdateController(
    current: version,
    source: GitHubUpdateSource(
      current: version,
      apiBase: apiBase,
      allowInsecure: allowInsecure,
    ),
    preferences: UpdatePreferences(appState),
    downloader: HttpApkDownloader(
      current: version,
      urlPolicy: policy,
    ),
    installer: MethodChannelApkInstaller(),
    now: now,
  );
}
