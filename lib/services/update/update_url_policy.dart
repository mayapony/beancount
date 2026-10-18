/// 更新源域名策略。
///
/// 正式构建只允许 `github.com` 下本仓库的 release 下载地址；debug 构建在
/// `UPDATE_API_BASE` 指向本地 mock feed 时，放行该 host 的 http 地址，便于联调。
class UpdateUrlPolicy {
  const UpdateUrlPolicy({required this.apiBase, this.allowInsecure = false});

  static final UpdateUrlPolicy github =
      UpdateUrlPolicy(apiBase: Uri.parse('https://api.github.com'));

  final Uri apiBase;
  final bool allowInsecure;

  bool get isCustom => apiBase.host != 'api.github.com';

  bool allowsApk(Uri uri) => _allowsReleaseAsset(uri);

  bool allowsChecksum(Uri uri) => _allowsReleaseAsset(uri);

  bool _allowsReleaseAsset(Uri uri) {
    if (uri.scheme != 'https' && !(allowInsecure && uri.scheme == 'http')) {
      return false;
    }
    if (allowInsecure && uri.host == apiBase.host) return true;
    return uri.host == 'github.com' &&
        uri.path.startsWith('/mayapony/beancount/releases/download/');
  }

  /// 检查 URL 是否指向本仓库的 release。
  bool allowsApiBase(Uri uri) =>
      uri.host == apiBase.host && uri.scheme == apiBase.scheme;
}
