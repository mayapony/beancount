/// 版本比较：只比较数字段，忽略 `v` 前缀、`+build` 与 `-prerelease` 后缀。
///
/// 发布源是 `releases/latest`，本身已排除 draft / prerelease；这里仍宽容处理
/// 后缀，避免 tag 里带 `-beta` 时把整条更新链路弄崩。
library;

/// 解析 `v1.2.3` / `1.2.3+4` / `1.2.3-beta`；非法输入返回 null。
List<int>? parseVersion(String raw) {
  var value = raw.trim();
  if (value.isEmpty) return null;
  value = value.replaceFirst(RegExp(r'^[vV]'), '');
  value = value.split('+').first;
  value = value.split('-').first;
  if (value.isEmpty) return null;

  final parts = value.split('.');
  final numbers = <int>[];
  for (final part in parts) {
    if (part.isEmpty || !RegExp(r'^\d+$').hasMatch(part)) return null;
    final number = int.tryParse(part);
    if (number == null) return null;
    numbers.add(number);
  }
  return numbers;
}

/// 把 tag 规范化为 versionName：`v1.2.3` → `1.2.3`；非法返回 null。
String? normalizeVersion(String raw) {
  final parts = parseVersion(raw);
  return parts?.join('.');
}

/// 比较两个版本号：a < b 返回负数，相等返回 0，a > b 返回正数。
///
/// 任一边非法时按「不可比较」处理，返回 0；调用方不要把非法版本当成新版本。
int compareVersions(String a, String b) {
  final left = parseVersion(a);
  final right = parseVersion(b);
  if (left == null || right == null) return 0;

  final length = left.length > right.length ? left.length : right.length;
  for (var i = 0; i < length; i++) {
    final l = i < left.length ? left[i] : 0;
    final r = i < right.length ? right[i] : 0;
    if (l != r) return l.compareTo(r);
  }
  return 0;
}

/// 候选版本是否比当前版本新；任一边非法时返回 false。
bool isNewerVersion(String candidate, String current) =>
    compareVersions(candidate, current) > 0;
