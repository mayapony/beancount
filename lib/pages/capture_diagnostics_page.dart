import 'dart:convert';

import 'package:flutter/material.dart';

import '../services/capture/capture_channel.dart';
import '../services/capture/capture_diagnostics.dart';
import '../services/capture/capture_rule.dart';
import '../services/capture/capture_settings.dart';
import '../theme/tokens.dart';
import '../widgets/common.dart';

/// 「诊断记录」：把自动记账与截图识别链路的每一次判断摊开给用户看。
///
/// 上半部分是当前状态（服务在不在跑、规则几条、上次捕获/入账多久前），
/// 下半部分是事件流。整条链路上唯一原本能看到的痕迹是「入账成功」，
/// 这里补上失败与放弃的那部分。
class CaptureDiagnosticsPage extends StatefulWidget {
  const CaptureDiagnosticsPage({
    super.key,
    required this.settings,
    required this.platform,
    required this.rules,
    required this.diag,
    this.lastAutoEntryAt,
  });

  final CaptureSettingsStore settings;
  final CapturePlatform platform;
  final CaptureRuleStore rules;
  final CaptureDiagnostics diag;

  /// 最近一笔自动入账的时间；为空表示这次不显示该行。
  final Future<DateTime?> Function()? lastAutoEntryAt;

  @override
  State<CaptureDiagnosticsPage> createState() => _CaptureDiagnosticsPageState();
}

class _CaptureDiagnosticsPageState extends State<CaptureDiagnosticsPage> {
  CaptureSettings _settings = const CaptureSettings();
  bool _accessibility = false;
  bool _notification = false;
  Map<String, Object?>? _service;
  List<CaptureRule> _rules = const [];
  List<CaptureDiagEvent> _events = const [];
  DateTime? _lastAutoEntry;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final settings = await widget.settings.load();
    final accessibility = await widget.platform.isAccessibilityEnabled();
    final notification = await widget.platform.isNotificationListenerEnabled();
    final service = await widget.platform.nativeServiceState();
    final rules = await widget.rules.load();
    final events = await _loadEvents();
    final lastEntry = await widget.lastAutoEntryAt?.call();
    if (!mounted) return;
    setState(() {
      _settings = settings;
      _accessibility = accessibility;
      _notification = notification;
      _service = service;
      _rules = rules;
      _events = events;
      _lastAutoEntry = lastEntry;
      _loading = false;
    });
  }

  /// 合并两源：Dart 侧 `app_state` 与原生侧 `SharedPreferences`，按时间倒序。
  Future<List<CaptureDiagEvent>> _loadEvents() async {
    final merged = <CaptureDiagEvent>[...await widget.diag.events()];
    final raw = await widget.platform.readNativeDiag();
    if (raw != null && raw.trim().isNotEmpty) {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is List) {
          for (final item in decoded) {
            final event = CaptureDiagEvent.fromJson(item);
            if (event != null) merged.add(event);
          }
        }
      } on FormatException {
        // 原生记录坏了不该让整页打不开
      }
    }
    merged.sort((a, b) {
      final byTime = b.at.compareTo(a.at);
      return byTime != 0 ? byTime : b.seq.compareTo(a.seq);
    });
    return merged;
  }

  Future<void> _clear() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('清空诊断记录？'),
        content: const Text('事件与保留的页面文本都会删除，之后的问题将无法追溯。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          TextButton(
            key: const Key('capture-diag-clear-confirm'),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('清空'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await widget.diag.clear();
    await widget.platform.clearNativeDiag();
    await _load();
  }

  int _countTier(CaptureRuleTier tier) =>
      _rules.where((rule) => rule.tier == tier).length;

  @override
  Widget build(BuildContext context) {
    final palette = BeanPalette.of(context);
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        leading: IconButton(
          tooltip: '返回',
          icon: const Icon(Icons.chevron_left_rounded, size: 28),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: const Text(
          '诊断记录',
          style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
        ),
        centerTitle: true,
        actions: [
          IconButton(
            key: const Key('capture-diag-clear'),
            tooltip: '清空记录',
            icon: const Icon(Icons.delete_outline_rounded, size: 22),
            onPressed: _clear,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(
                  BeanSpace.page,
                  8,
                  BeanSpace.page,
                  120,
                ),
                children: [
                  BeanLargeTitle(
                    title: '诊断记录',
                    subtitle: '下拉刷新 · 最近 ${_events.length} 条',
                  ),
                  const SizedBox(height: 8),
                  _StatusCard(
                    settings: _settings,
                    accessibility: _accessibility,
                    notification: _notification,
                    service: _service,
                    rules: _rules,
                    greyCount: _countTier(CaptureRuleTier.grey),
                    pendingCount: _countTier(CaptureRuleTier.pending),
                    activeCount: _countTier(CaptureRuleTier.active),
                    lastAutoEntry: _lastAutoEntry,
                  ),
                  if (_rules.isEmpty) ...[
                    const SizedBox(height: 10),
                    _Hint(
                      key: const Key('capture-diag-no-rules'),
                      color: palette.alert,
                      icon: Icons.warning_amber_rounded,
                      text: '还没有任何提取规则，自动记账不会触发。'
                          '先在支付页截一张图，让规则从本次留证里生成。',
                    ),
                  ],
                  const SizedBox(height: 18),
                  Text(
                    '事件流',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: palette.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 8),
                  if (_events.isEmpty)
                    const BeanEmptyState(
                      icon: Icons.timeline_rounded,
                      title: '还没有记录',
                      subtitle: '开启自动记账后，每一次捕获与放弃都会记在这里',
                    )
                  else
                    BeanCard(
                      padding: EdgeInsets.zero,
                      child: Column(
                        children: [
                          for (var i = 0; i < _events.length; i++) ...[
                            if (i > 0)
                              Divider(
                                height: BeanSpace.hairline,
                                thickness: BeanSpace.hairline,
                                indent: 52,
                                color: palette.border,
                              ),
                            _EventTile(
                              event: _events[i],
                              diag: widget.diag,
                            ),
                          ],
                        ],
                      ),
                    ),
                ],
              ),
            ),
    );
  }
}

class _StatusCard extends StatelessWidget {
  const _StatusCard({
    required this.settings,
    required this.accessibility,
    required this.notification,
    required this.service,
    required this.rules,
    required this.greyCount,
    required this.pendingCount,
    required this.activeCount,
    required this.lastAutoEntry,
  });

  final CaptureSettings settings;
  final bool accessibility;
  final bool notification;
  final Map<String, Object?>? service;
  final List<CaptureRule> rules;
  final int greyCount;
  final int pendingCount;
  final int activeCount;
  final DateTime? lastAutoEntry;

  bool get _serviceRunning => service?['running'] == true;

  DateTime? get _serviceStartedAt {
    final raw = service?['started_at'];
    if (raw is int && raw > 0) {
      return DateTime.fromMillisecondsSinceEpoch(raw);
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final palette = BeanPalette.of(context);
    return BeanCard(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      child: Column(
        children: [
          _row(
            palette,
            '自动记账',
            settings.enabled ? '已开启' : '已关闭',
            ok: settings.enabled,
          ),
          _row(
            palette,
            '无障碍权限',
            accessibility ? '已开启' : '未开启',
            ok: accessibility,
          ),
          _row(
            palette,
            '通知使用权',
            notification ? '已开启' : '未开启',
            ok: notification,
          ),
          _row(
            palette,
            '后台服务',
            _serviceRunning
                ? '运行中${_serviceStartedAt == null ? '' : ' · ${_clock(_serviceStartedAt!)}'}'
                : (service == null ? '原生未报告' : '未运行'),
            ok: _serviceRunning,
          ),
          _row(
            palette,
            '提取规则',
            rules.isEmpty
                ? '0 条'
                : '${rules.length} 条 · 灰度 $greyCount / 待定 $pendingCount / 自动 $activeCount',
            ok: rules.isNotEmpty,
          ),
          _row(palette, '上次捕获', _relative(settings.lastCaptureAt)),
          _row(palette, '上次入账', _relative(lastAutoEntry)),
        ],
      ),
    );
  }

  Widget _row(
    BeanPalette palette,
    String label,
    String value, {
    bool? ok,
  }) {
    final color = ok == null
        ? palette.textSecondary
        : (ok ? BeanColors.beanGreen : palette.alert);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 82,
            child: Text(
              label,
              style: TextStyle(fontSize: 13, color: palette.textSecondary),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(fontSize: 13, color: color),
            ),
          ),
        ],
      ),
    );
  }

  static String _clock(DateTime at) {
    final two = at.hour.toString().padLeft(2, '0');
    final minute = at.minute.toString().padLeft(2, '0');
    return '$two:$minute 启动';
  }

  static String _relative(DateTime? at) {
    if (at == null) return '从未';
    final gap = DateTime.now().difference(at);
    if (gap.inMinutes < 1) return '刚刚';
    if (gap.inMinutes < 60) return '${gap.inMinutes} 分钟前';
    if (gap.inHours < 24) return '${gap.inHours} 小时前';
    return '${gap.inDays} 天前';
  }
}

class _Hint extends StatelessWidget {
  const _Hint({
    super.key,
    required this.color,
    required this.icon,
    required this.text,
  });

  final Color color;
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 16, color: color),
        const SizedBox(width: 6),
        Expanded(
          child: Text(text, style: TextStyle(fontSize: 12, color: color)),
        ),
      ],
    );
  }
}

class _EventTile extends StatefulWidget {
  const _EventTile({required this.event, required this.diag});

  final CaptureDiagEvent event;
  final CaptureDiagnostics diag;

  @override
  State<_EventTile> createState() => _EventTileState();
}

class _EventTileState extends State<_EventTile> {
  bool _open = false;
  String? _evidence;
  bool _evidenceLoaded = false;

  Future<void> _toggle() async {
    setState(() => _open = !_open);
    if (!_open || _evidenceLoaded) return;
    _evidenceLoaded = true;
    final id = widget.event.evidenceId;
    if (id == null) return;
    final text = await widget.diag.evidence.read(id);
    if (!mounted) return;
    setState(() => _evidence = text);
  }

  @override
  Widget build(BuildContext context) {
    final palette = BeanPalette.of(context);
    final event = widget.event;
    final accent = event.ok ? BeanColors.beanGreen : palette.alert;
    return InkWell(
      key: Key('capture-diag-event-${event.seq}-${event.kind.wire}'),
      onTap: _toggle,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 14, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  event.ok
                      ? Icons.check_circle_outline_rounded
                      : Icons.error_outline_rounded,
                  size: 18,
                  color: accent,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        [
                          event.kind.label,
                          if (event.packageName != null) event.packageName!,
                          if (event.count > 1) '×${event.count}',
                        ].join(' · '),
                        style: const TextStyle(fontSize: 14, height: 1.25),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        [
                          _time(event.at),
                          if (event.reason != null) event.reason!,
                        ].join(' · '),
                        style: TextStyle(
                          fontSize: 12,
                          color: palette.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(
                  _open ? Icons.expand_less_rounded : Icons.expand_more_rounded,
                  size: 18,
                  color: palette.textSecondary,
                ),
              ],
            ),
            if (_open) ...[
              const SizedBox(height: 8),
              _FingerprintDiff(event: event),
              _DetailTable(detail: event.detail),
              _EvidenceText(event: event, evidence: _evidence),
            ],
          ],
        ),
      ),
    );
  }

  static String _time(DateTime at) {
    final h = at.hour.toString().padLeft(2, '0');
    final m = at.minute.toString().padLeft(2, '0');
    final s = at.second.toString().padLeft(2, '0');
    return '$h:$m:$s';
  }
}

/// 「本次指纹」与「规则库里已有的指纹」左右对照：一条记录就能看出是不是
/// 页面结构变了导致规则不再命中。
class _FingerprintDiff extends StatelessWidget {
  const _FingerprintDiff({required this.event});

  final CaptureDiagEvent event;

  @override
  Widget build(BuildContext context) {
    final palette = BeanPalette.of(context);
    final current = event.detail['fingerprint']?.toString();
    final rules = event.detail['rules'];
    if (current == null && rules is! List) return const SizedBox.shrink();
    final existing = <String>[];
    if (rules is List) {
      for (final rule in rules) {
        if (rule is Map && rule['fingerprint'] != null) {
          existing.add(
            '${rule['tier'] ?? '?'} ${rule['fingerprint']}',
          );
        }
      }
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '本次指纹 ${current ?? '—'}',
            key: const Key('capture-diag-fingerprint-current'),
            style: TextStyle(fontSize: 12, color: palette.textSecondary),
          ),
          Text(
            existing.isEmpty ? '规则库指纹 无' : '规则库指纹 ${existing.join(' / ')}',
            key: const Key('capture-diag-fingerprint-existing'),
            style: TextStyle(fontSize: 12, color: palette.textSecondary),
          ),
        ],
      ),
    );
  }
}

class _DetailTable extends StatelessWidget {
  const _DetailTable({required this.detail});

  final Map<String, Object?> detail;

  @override
  Widget build(BuildContext context) {
    final palette = BeanPalette.of(context);
    if (detail.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final entry in detail.entries)
          if (entry.key != 'fingerprint' && entry.key != 'rules')
            Padding(
              padding: const EdgeInsets.only(bottom: 2),
              child: Text(
                '${entry.key}: ${_stringify(entry.value)}',
                style: TextStyle(
                  fontSize: 12,
                  height: 1.35,
                  color: palette.textSecondary,
                  fontFamily: 'monospace',
                ),
              ),
            ),
      ],
    );
  }

  static String _stringify(Object? value) {
    if (value is Map) {
      return value.entries
          .map((e) => '${e.key}=${_stringify(e.value)}')
          .join(', ');
    }
    if (value is List) {
      return '[${value.map(_stringify).join(', ')}]';
    }
    return value?.toString() ?? 'null';
  }
}

class _EvidenceText extends StatelessWidget {
  const _EvidenceText({required this.event, required this.evidence});

  final CaptureDiagEvent event;
  final String? evidence;

  @override
  Widget build(BuildContext context) {
    final palette = BeanPalette.of(context);
    if (event.evidenceId == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '完整现场',
            style: TextStyle(fontSize: 12, color: palette.textSecondary),
          ),
          const SizedBox(height: 2),
          Text(
            evidence ?? '证据已淘汰',
            style: TextStyle(
              fontSize: 11,
              height: 1.35,
              color: palette.textSecondary,
              fontFamily: 'monospace',
            ),
          ),
        ],
      ),
    );
  }
}
