import 'package:flutter/material.dart';

import '../data/repositories/theme_repository.dart';

/// 主题控制器：App 层用它驱动 `MaterialApp.themeMode`，设置页用它改值。
///
/// 为什么不用回调层层传递：`MaterialApp` 在 `ShellPage` 上层，
/// 而入口在更下层，用 `ChangeNotifier` 反着驱动更直接。
class ThemeController extends ChangeNotifier {
  ThemeController({required ThemeRepository repository, ThemeMode initial = ThemeMode.system})
      : _repository = repository,
        _mode = initial;

  final ThemeRepository _repository;
  ThemeMode _mode;

  ThemeMode get mode => _mode;

  String get label => ThemeRepository.labelOf(_mode);

  /// 启动时调用：读已保存的偏好。
  Future<void> load() async {
    final mode = await _repository.load();
    if (mode == _mode) return;
    _mode = mode;
    notifyListeners();
  }

  /// 选择新档位：内存先改（界面立即响应），再落库。
  Future<void> setThemeMode(ThemeMode mode) async {
    if (mode == _mode) return;
    _mode = mode;
    notifyListeners();
    try {
      await _repository.save(mode);
    } catch (_) {
      // 写库失败不回滚界面：本次会话仍然按用户选的样子显示
    }
  }
}
