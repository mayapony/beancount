import 'package:drift/drift.dart';
import 'package:flutter/material.dart';

import '../db/app_database.dart';

/// 主题偏好：`app_state.theme_mode` 存 `system|light|dark`。
///
/// 用字符串而不是整数：换版本时人眼可读，值也不会错位。
class ThemeRepository {
  ThemeRepository(this._db);

  final AppDatabase _db;

  static const key = 'theme_mode';

  Future<ThemeMode> load() async {
    try {
      final row = await (_db.select(_db.appState)
            ..where((t) => t.key.equals(key)))
          .getSingleOrNull();
      return _decode(row?.value);
    } catch (_) {
      // 读不到就跟随系统：不能因为存储异常把界面卡住
      return ThemeMode.system;
    }
  }

  Future<void> save(ThemeMode mode) async {
    await _db.into(_db.appState).insert(
          AppStateCompanion.insert(key: key, value: _encode(mode)),
          mode: InsertMode.insertOrReplace,
        );
  }

  static ThemeMode _decode(String? raw) => switch (raw) {
        'light' => ThemeMode.light,
        'dark' => ThemeMode.dark,
        _ => ThemeMode.system,
      };

  static String _encode(ThemeMode mode) => switch (mode) {
        ThemeMode.light => 'light',
        ThemeMode.dark => 'dark',
        ThemeMode.system => 'system',
      };

  /// 界面上显示的名字。
  static String labelOf(ThemeMode mode) => switch (mode) {
        ThemeMode.light => '浅色',
        ThemeMode.dark => '深色',
        ThemeMode.system => '跟随系统',
      };
}
