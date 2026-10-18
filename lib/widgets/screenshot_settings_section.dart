import 'package:flutter/material.dart';

import '../services/screenshot/screenshot_settings.dart';
import '../theme/tokens.dart';
import 'common.dart';

/// 申请截屏自动识别所需的系统权限；返回 false 表示用户拒绝。
typedef ScreenshotPermissionRequest = Future<bool> Function();

/// 设置页里的「截屏自动识别」区块。
///
/// 三个开关都默认关闭；打开总开关时先申请权限，被拒绝就保持关闭并说明原因。
/// 真正的监听服务由 [onAutoEntryChanged] 的接收方启停（Android 原生侧）。
class ScreenshotSettingsSection extends StatefulWidget {
  const ScreenshotSettingsSection({
    super.key,
    required this.store,
    this.requestPermissions,
    this.onAutoEntryChanged,
  });

  final ScreenshotSettingsStore store;

  /// 为空时（测试/非 Android）只保存开关，不申请权限。
  final ScreenshotPermissionRequest? requestPermissions;

  /// 总开关变化后的回调，用于启停后台服务。
  final ValueChanged<bool>? onAutoEntryChanged;

  @override
  State<ScreenshotSettingsSection> createState() =>
      _ScreenshotSettingsSectionState();
}

class _ScreenshotSettingsSectionState extends State<ScreenshotSettingsSection> {
  ScreenshotSettings _settings = const ScreenshotSettings();
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final settings = await widget.store.load();
    if (!mounted) return;
    setState(() => _settings = settings);
  }

  Future<void> _save(ScreenshotSettings next) async {
    setState(() => _settings = next);
    await widget.store.save(next);
  }

  Future<void> _setAutoEntry(bool value) async {
    if (_busy) return;
    if (value) {
      final request = widget.requestPermissions;
      if (request != null) {
        setState(() => _busy = true);
        final granted = await request();
        if (!mounted) return;
        setState(() => _busy = false);
        if (!granted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('未授权相册读取或通知，截屏自动识别保持关闭')),
          );
          widget.onAutoEntryChanged?.call(false);
          return;
        }
      }
    }
    await _save(_settings.copyWith(autoEntry: value));
    widget.onAutoEntryChanged?.call(value);
  }

  @override
  Widget build(BuildContext context) {
    final palette = BeanPalette.of(context);
    return BeanCard(
      padding: EdgeInsets.zero,
      child: Column(
        children: [
          SwitchListTile.adaptive(
            key: const Key('screenshot-auto-entry-switch'),
            value: _settings.autoEntry,
            onChanged: _busy ? null : _setAutoEntry,
            secondary: const Icon(
              Icons.screenshot_monitor_rounded,
              color: Color(0xFF0EA5E9),
            ),
            title: const Text('截屏自动识别', style: TextStyle(fontSize: 15)),
            subtitle: Text(
              _settings.autoEntry
                  ? '后台监听截屏，检测到就上传识别'
                  : '关闭时不监听、不上传',
              style: TextStyle(fontSize: 12, color: palette.textSecondary),
            ),
          ),
          if (_settings.autoEntry) ...[
            _divider(palette),
            Padding(
              key: const Key('screenshot-permission-hint'),
              padding: const EdgeInsets.fromLTRB(56, 8, 16, 10),
              child: Text(
                '需要「读取照片」与通知权限；常驻通知说明正在监听，可随时关闭。',
                style: TextStyle(fontSize: 12, color: palette.textSecondary),
              ),
            ),
          ],
          _divider(palette),
          SwitchListTile.adaptive(
            key: const Key('auto-create-categories-switch'),
            value: _settings.autoCreateCategories,
            onChanged: (value) => _save(
              _settings.copyWith(autoCreateCategories: value),
            ),
            secondary: const Icon(
              Icons.create_new_folder_outlined,
              color: BeanColors.goldDeep,
            ),
            title: const Text('自动新建分类', style: TextStyle(fontSize: 15)),
            subtitle: Text(
              '识别出词表内的新分类时，保存那笔账才创建（7 天最多 3 个）',
              style: TextStyle(fontSize: 12, color: palette.textSecondary),
            ),
          ),
          _divider(palette),
          SwitchListTile.adaptive(
            key: const Key('auto-tags-switch'),
            value: _settings.autoTags,
            onChanged: (value) => _save(_settings.copyWith(autoTags: value)),
            secondary: const Icon(
              Icons.sell_outlined,
              color: Color(0xFF8B5CF6),
            ),
            title: const Text('自动打标签', style: TextStyle(fontSize: 15)),
            subtitle: Text(
              '只用词表内的标签，单笔最多 2 个，保存时创建',
              style: TextStyle(fontSize: 12, color: palette.textSecondary),
            ),
          ),
        ],
      ),
    );
  }
}

Widget _divider(BeanPalette palette) => Divider(
      height: BeanSpace.hairline,
      thickness: BeanSpace.hairline,
      indent: 60,
      color: palette.border,
    );
