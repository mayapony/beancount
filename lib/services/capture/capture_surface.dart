library;

import 'dart:convert';

import '../../data/repositories/app_state_repository.dart';

/// 「截图优先」的 surface 标记：树读不出来（自绘 / WebView / FLAG_SECURE）的页面。
///
/// 这些 surface 永远生成不出好规则，标记后不再反复尝试生成，直接走截图兜底。
/// 键是「包名 + | + 指纹」；树为空时指纹退化为固定值，等同于整包标记。
class CaptureSurfaceStore {
  CaptureSurfaceStore(this._state);

  final AppStateRepository _state;

  static const kKey = 'capture_screenshot_first_surfaces';

  Future<Set<String>> load() async {
    final raw = await _state.read(kKey);
    if (raw == null || raw.trim().isEmpty) return const <String>{};
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const <String>{};
      return decoded.whereType<String>().toSet();
    } on FormatException {
      return const <String>{};
    }
  }

  Future<void> mark(String packageName, String fingerprint) async {
    final surfaces = Set<String>.from(await load());
    surfaces.add('$packageName|$fingerprint');
    await _state.write(kKey, jsonEncode(surfaces.toList()..sort()));
  }

  Future<bool> isMarked(String packageName, String fingerprint) async {
    final surfaces = await load();
    return surfaces.contains('$packageName|$fingerprint');
  }
}
