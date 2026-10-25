import 'package:flutter/material.dart';

import '../services/capture/capture_channel.dart';
import '../services/capture/capture_settings.dart';
import '../theme/tokens.dart';
import 'common.dart';

/// 设置页里的「自动记账」区块（无障碍 + 通知监听）。
///
/// 默认关闭；开启后引导用户完成系统授权（无障碍 + 通知使用权），并给出
/// Android 13+ 侧载「允许受限设置」说明。失效心跳（连续 7 天零捕获）也在这里
/// 提示。真正的后台服务由 [CapturePlatform.setEnabled] 启停（Android 原生侧）。
class CaptureSettingsSection extends StatefulWidget {
  const CaptureSettingsSection({
    super.key,
    required this.store,
    required this.platform,
    required this.onOpenAutoEntries,
  });

  final CaptureSettingsStore store;
  final CapturePlatform platform;

  /// 打开「最近自动记账」列表。
  final VoidCallback onOpenAutoEntries;

  @override
  State<CaptureSettingsSection> createState() => _CaptureSettingsSectionState();
}

class _CaptureSettingsSectionState extends State<CaptureSettingsSection>
    with WidgetsBindingObserver {
  CaptureSettings _settings = const CaptureSettings();
  bool _accessibilityEnabled = false;
  bool _notificationEnabled = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _load();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // 从系统授权页回来时刷新授权状态
    if (state == AppLifecycleState.resumed) _load();
  }

  Future<void> _load() async {
    final settings = await widget.store.load();
    final accessibility = await widget.platform.isAccessibilityEnabled();
    final notification = await widget.platform.isNotificationListenerEnabled();
    if (!mounted) return;
    setState(() {
      _settings = settings;
      _accessibilityEnabled = accessibility;
      _notificationEnabled = notification;
    });
  }

  Future<void> _setEnabled(bool value) async {
    await widget.store.setEnabled(value);
    await widget.platform.setEnabled(value);
    if (!mounted) return;
    setState(() => _settings = _settings.copyWith(enabled: value));
  }

  Future<void> _openAccessibility() async {
    await widget.platform.openAccessibilitySettings();
    await _load();
  }

  Future<void> _openNotification() async {
    await widget.platform.openNotificationListenerSettings();
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    // Android-only 门：非 Android / Web 直接不渲染，无入口、无报错。
    if (!widget.platform.isSupported) return const SizedBox.shrink();

    final palette = BeanPalette.of(context);
    final stale = isCaptureStale(
      enabled: _settings.enabled,
      lastCaptureAt: _settings.lastCaptureAt,
    );

    return BeanCard(
      padding: EdgeInsets.zero,
      child: Column(
        children: [
          SwitchListTile.adaptive(
            key: const Key('capture-auto-entry-switch'),
            value: _settings.enabled,
            onChanged: _setEnabled,
            secondary: const Icon(
              Icons.bolt_rounded,
              color: BeanColors.gold,
            ),
            title: const Text('自动记账', style: TextStyle(fontSize: 15)),
            subtitle: Text(
              _settings.enabled
                  ? '无障碍 + 通知监听，支付后直接入账'
                  : '默认关闭，开启后需授权无障碍与通知使用权',
              style: TextStyle(fontSize: 12, color: palette.textSecondary),
            ),
          ),
          if (_settings.enabled) ...[
            _divider(palette),
            Padding(
              key: const Key('capture-permission-hint'),
              padding: const EdgeInsets.fromLTRB(56, 8, 16, 8),
              child: Text(
                '需要在系统设置里开启「金豆 · 自动记账」的无障碍与通知使用权，'
                '支付发生时才读得到金额。Android 13+ 侧载应用若开关是灰的，'
                '请进「应用信息 → 允许受限设置」后再开。',
                style: TextStyle(fontSize: 12, color: palette.textSecondary),
              ),
            ),
            _AuthRow(
              label: '无障碍权限',
              enabled: _accessibilityEnabled,
              actionLabel: '去开启',
              onAction: _openAccessibility,
            ),
            _divider(palette),
            _AuthRow(
              label: '通知使用权',
              enabled: _notificationEnabled,
              actionLabel: '去开启',
              onAction: _openNotification,
            ),
            if (stale) ...[
              _divider(palette),
              Padding(
                key: const Key('capture-stale-hint'),
                padding: const EdgeInsets.fromLTRB(56, 10, 16, 10),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      Icons.warning_amber_rounded,
                      size: 16,
                      color: palette.alert,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        '自动记账可能已失效：连续 7 天没记到支付，请检查授权或目标应用是否改版。',
                        style: TextStyle(fontSize: 12, color: palette.alert),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            _divider(palette),
            ListTile(
              key: const Key('capture-auto-entries-entry'),
              leading: const Icon(
                Icons.receipt_long_rounded,
                color: BeanColors.beanGreen,
              ),
              title: const Text('最近自动记账', style: TextStyle(fontSize: 15)),
              subtitle: const Text('核对、修改或删除自动入账'),
              trailing: const Icon(Icons.chevron_right_rounded, size: 20),
              onTap: widget.onOpenAutoEntries,
            ),
          ],
        ],
      ),
    );
  }

  Widget _divider(BeanPalette palette) => Divider(
        height: BeanSpace.hairline,
        thickness: BeanSpace.hairline,
        indent: 60,
        color: palette.border,
      );
}

class _AuthRow extends StatelessWidget {
  const _AuthRow({
    required this.label,
    required this.enabled,
    required this.actionLabel,
    required this.onAction,
  });

  final String label;
  final bool enabled;
  final String actionLabel;
  final VoidCallback onAction;

  @override
  Widget build(BuildContext context) {
    final palette = BeanPalette.of(context);
    return ListTile(
      dense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16),
      leading: Icon(
        enabled ? Icons.check_circle_rounded : Icons.radio_button_unchecked_rounded,
        size: 20,
        color: enabled ? BeanColors.beanGreen : palette.textSecondary,
      ),
      title: Text(
        enabled ? '$label · 已开启' : '$label · 未开启',
        style: const TextStyle(fontSize: 14),
      ),
      trailing: TextButton(
        onPressed: onAction,
        child: Text(actionLabel),
      ),
    );
  }
}
