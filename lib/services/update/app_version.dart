import 'package:package_info_plus/package_info_plus.dart';

/// 读取平台包信息；测试可注入。
typedef PackageInfoLoader = Future<PackageInfo> Function();

/// 当前安装包的版本信息。
///
/// 只依赖平台包信息，不读 `pubspec.yaml`，也不允许页面写死版本号。
class AppVersion {
  const AppVersion({required this.version, required this.buildNumber});

  final String version;
  final String buildNumber;

  static const unknown = AppVersion(version: '', buildNumber: '');

  bool get isKnown => version.trim().isNotEmpty;

  /// 规范化后的 versionName（去掉可能存在的 `v` 前缀）。
  String? get normalized {
    if (!isKnown) return null;
    return version.trim().replaceFirst(RegExp(r'^[vV]'), '');
  }

  /// 关于页展示用：有版本时 `v1.0.1`，读不到时「版本未知」。
  String get label => isKnown ? 'v${normalized!}' : '版本未知';

  /// 带 build 号的完整展示，例如 `v1.0.1 (2)`。
  String get fullLabel =>
      buildNumber.trim().isEmpty ? label : '$label (${buildNumber.trim()})';

  factory AppVersion.fromPackageInfo(PackageInfo info) => AppVersion(
        version: info.version,
        buildNumber: info.buildNumber,
      );

  @override
  bool operator ==(Object other) =>
      other is AppVersion &&
      other.version == version &&
      other.buildNumber == buildNumber;

  @override
  int get hashCode => Object.hash(version, buildNumber);

  @override
  String toString() => 'AppVersion($version+$buildNumber)';
}

/// 读平台包信息；任何异常都回落为 [AppVersion.unknown]，不能因为读不到版本把页面弄崩。
Future<AppVersion> loadAppVersion({PackageInfoLoader? loader}) async {
  try {
    final info = await (loader ?? () => PackageInfo.fromPlatform())();
    return AppVersion.fromPackageInfo(info);
  } catch (_) {
    return AppVersion.unknown;
  }
}
