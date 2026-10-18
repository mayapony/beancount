import 'apk_installer.dart';
import 'update_models.dart';

/// 安装失败的统一文案。签名不一致时必须明确提示先导出，绝不能引导卸载了事。
String installFailureMessage(UpdateFailureKind kind) {
  return switch (kind) {
    UpdateFailureKind.permission => '需要允许金豆安装未知应用',
    UpdateFailureKind.downgrade => '安装包版本低于当前版本，系统会拒绝安装',
    UpdateFailureKind.signature =>
      '安装包与当前 App 签名不一致，无法覆盖安装。请先导出数据备份，再卸载重装；或安装与当前签名一致的包。',
    UpdateFailureKind.versionName => '安装包版本与发布信息不一致，已阻止安装',
    UpdateFailureKind.parse => '安装包损坏或不是有效的 APK',
    UpdateFailureKind.noInstaller => '系统没有可用的安装器',
    _ => '安装失败，请重试',
  };
}

/// 把 Kotlin preflight 的 reason 映射成可展示的失败。
UpdateFailure failureForPreflight(ApkPreflight preflight) {
  final kind = switch (preflight.reason) {
    'downgrade' => UpdateFailureKind.downgrade,
    'signature' => UpdateFailureKind.signature,
    'versionName' => UpdateFailureKind.versionName,
    'parse' => UpdateFailureKind.parse,
    'noInstaller' => UpdateFailureKind.noInstaller,
    _ => UpdateFailureKind.unknown,
  };
  return UpdateFailure(kind, installFailureMessage(kind));
}
