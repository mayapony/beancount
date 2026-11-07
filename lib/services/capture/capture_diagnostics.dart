library;

import 'dart:convert';

import '../../data/repositories/app_state_repository.dart';

/// 一条运行记录的类别：捕获与识别链路上每一个可能「停下」的位置各有一类。
///
/// `wire` 是落盘用的稳定字符串，改枚举名不会污染历史记录。
enum CaptureDiagKind {
  /// 开关关闭 / 授权缺失等前置门。
  gateClosed('gate_closed', '前置条件未满足'),

  /// 无障碍抓到一帧控件树。
  treeCaptured('tree_captured', '抓到页面'),

  /// 通知监听收到一条通知。
  notifCaptured('notif_captured', '收到通知'),

  /// 没有可用规则（规则库为空，或没有一条匹配当前包 / 页面）。
  noRule('no_rule', '没有可用规则'),

  /// 命中了规则但规则仍是待定档，不参与自动入账。
  pendingRule('pending_rule', '规则待定'),

  /// 规则命中但提取不出金额。
  noExtraction('no_extraction', '没提取出金额'),

  /// 入账成功。
  entryWritten('entry_written', '入账成功'),

  /// 入账写库失败。
  writeFailed('write_failed', '入账失败'),

  /// 视觉模型识别返回。
  llmRecognize('llm_recognize', '识别返回'),

  /// 云端生成规则返回。
  llmRuleGen('llm_rule_gen', '规则生成返回'),

  /// 规则学习被跳过。
  learnSkipped('learn_skipped', '学习跳过'),

  /// 事件因后台引擎未就绪被丢弃（原生侧记录）。
  eventDropped('event_dropped', '事件被丢弃'),

  /// 找不到可读的应用窗口（原生侧记录）。
  windowMissing('window_missing', '读不到窗口');

  const CaptureDiagKind(this.wire, this.label);

  /// 落盘用的稳定标识。
  final String wire;

  /// 界面上的一句话说明。
  final String label;

  static CaptureDiagKind? fromWire(Object? raw) {
    final name = raw?.toString();
    if (name == null) return null;
    for (final kind in values) {
      if (kind.wire == name) return kind;
    }
    return null;
  }
}

/// 一条运行记录。
///
/// 只描述「发生了什么」，不含任何判定逻辑；[detail] 放该类别专属字段（指纹、
/// 模型原文、规则内容等），由埋点方决定。
class CaptureDiagEvent {
  const CaptureDiagEvent({
    required this.seq,
    required this.at,
    required this.kind,
    this.packageName,
    this.target,
    this.ok = true,
    this.reason,
    this.detail = const {},
    this.evidenceId,
    this.count = 1,
  });

  /// 同源内单调递增，跨源只用 [at] 排序。
  final int seq;

  final DateTime at;
  final CaptureDiagKind kind;

  /// 触发事件的包名（截图识别链路可能为空）。
  final String? packageName;

  /// `accessibility` / `notification`，没有目标区分时为空。
  final String? target;

  /// 这条记录代表的结果是成功还是失败。
  final bool ok;

  /// 失败或跳过的机器可读原因，如 `no_rule`、`empty_tree`。
  final String? reason;

  final Map<String, Object?> detail;

  /// 指向 [`CaptureDiagStore`] 里保留的完整现场（树文本 / 模型原文）。
  final String? evidenceId;

  /// 同类事件在 1 秒窗口内被合并的次数。
  final int count;

  CaptureDiagEvent copyWith({int? count, String? evidenceId}) => CaptureDiagEvent(
        seq: seq,
        at: at,
        kind: kind,
        packageName: packageName,
        target: target,
        ok: ok,
        reason: reason,
        detail: detail,
        evidenceId: evidenceId ?? this.evidenceId,
        count: count ?? this.count,
      );

  Map<String, Object?> toJson() => {
        'seq': seq,
        'at': at.toUtc().toIso8601String(),
        'kind': kind.wire,
        if (packageName != null) 'package': packageName,
        if (target != null) 'target': target,
        'ok': ok,
        if (reason != null) 'reason': reason,
        if (detail.isNotEmpty) 'detail': detail,
        if (evidenceId != null) 'evidence': evidenceId,
        if (count > 1) 'count': count,
      };

  /// 宽容解析：字段缺失用默认值，类别不认识时返回 null（旧版本写的新类别
  /// 不该让整份记录读不出来）。
  static CaptureDiagEvent? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final kind = CaptureDiagKind.fromWire(raw['kind']);
    if (kind == null) return null;
    final at = DateTime.tryParse(raw['at']?.toString() ?? '');
    if (at == null) return null;
    final seq = _int(raw['seq']) ?? at.toUtc().microsecondsSinceEpoch;
    return CaptureDiagEvent(
      seq: seq,
      at: at.toLocal(),
      kind: kind,
      packageName: raw['package']?.toString(),
      target: raw['target']?.toString(),
      ok: raw['ok'] is bool ? raw['ok'] as bool : true,
      reason: raw['reason']?.toString(),
      detail: _detail(raw['detail']),
      evidenceId: raw['evidence']?.toString(),
      count: _int(raw['count']) ?? 1,
    );
  }

  static Map<String, Object?> _detail(Object? raw) {
    if (raw is! Map) return const {};
    return {
      for (final entry in raw.entries)
        entry.key.toString(): entry.value,
    };
  }

  static int? _int(Object? raw) {
    if (raw is int) return raw;
    if (raw is num) return raw.toInt();
    return int.tryParse(raw?.toString() ?? '');
  }
}

/// 运行记录的本地存储：`app_state` 里按 `diag_event:` 前缀的环形，只保留最近
/// [maxEvents] 条，超出淘汰最旧的。
///
/// 键名把序号左补零到 19 位，字典序即时间序；淘汰时不必解析每一条 JSON。
class CaptureDiagStore {
  CaptureDiagStore(
    this._state, {
    this.maxEvents = kMaxEvents,
  });

  final AppStateRepository _state;
  final int maxEvents;

  static const kEventPrefix = 'diag_event:';
  static const kMaxEvents = 200;

  Future<void> record(CaptureDiagEvent event) async {
    await _state.write(_keyFor(event.seq), jsonEncode(event.toJson()));
    await _prune(kEventPrefix, maxEvents);
  }

  /// 按时间升序读出全部事件；解不出来的行跳过，不影响其余记录。
  Future<List<CaptureDiagEvent>> readAll() async {
    final events = <CaptureDiagEvent>[];
    for (final row in await _state.readStartingWith(kEventPrefix)) {
      final event = _decode(row.value);
      if (event != null) events.add(event);
    }
    events.sort((a, b) {
      final byTime = a.at.compareTo(b.at);
      return byTime != 0 ? byTime : a.seq.compareTo(b.seq);
    });
    return events;
  }

  Future<void> clear() async {
    for (final row in await _state.readStartingWith(kEventPrefix)) {
      await _state.removeIfPresent(row.key);
    }
  }

  static String _keyFor(int seq) => '$kEventPrefix${seq.toString().padLeft(19, '0')}';

  static CaptureDiagEvent? _decode(String? raw) {
    if (raw == null || raw.trim().isEmpty) return null;
    try {
      return CaptureDiagEvent.fromJson(jsonDecode(raw));
    } on FormatException {
      return null;
    }
  }

  Future<void> _prune(String prefix, int max) async {
    final rows = await _state.readStartingWith(prefix);
    if (rows.length <= max) return;
    rows.sort((a, b) => a.key.compareTo(b.key));
    for (final row in rows.take(rows.length - max)) {
      await _state.removeIfPresent(row.key);
    }
  }
}

/// 完整现场（页面树文本 / 模型原文）的环形：只保留最近 [kMaxEvidence] 条。
///
/// 事件里用 [CaptureDiagEvent.evidenceId] 引用它；被淘汰后事件仍在，重读时为
/// null，界面显示「证据已淘汰」，不会让整条记录失败。
class CaptureDiagEvidenceStore {
  CaptureDiagEvidenceStore(this._state, {this.maxEvidence = kMaxEvidence});

  final AppStateRepository _state;
  final int maxEvidence;

  static const kEvidencePrefix = 'diag_evidence:';
  static const kMaxEvidence = 10;

  /// 存入一份现场并返回它的 id；超出容量时淘汰最旧的。
  Future<String> save(String text, {required DateTime at}) async {
    final id = 'ev-${at.toUtc().microsecondsSinceEpoch}';
    await _state.write(
      '$kEvidencePrefix$id',
      jsonEncode({
        'id': id,
        'at': at.toUtc().toIso8601String(),
        'text': text,
      }),
    );
    await _prune();
    return id;
  }

  /// 读一份现场；已被淘汰时返回 null。
  Future<String?> read(String id) async {
    final raw = await _state.read('$kEvidencePrefix$id');
    if (raw == null || raw.trim().isEmpty) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return null;
      return decoded['text']?.toString();
    } on FormatException {
      return null;
    }
  }

  Future<void> clear() async {
    for (final row in await _state.readStartingWith(kEvidencePrefix)) {
      await _state.removeIfPresent(row.key);
    }
  }

  Future<void> _prune() async {
    final rows = await _state.readStartingWith(kEvidencePrefix);
    if (rows.length <= maxEvidence) return;
    rows.sort((a, b) => a.key.compareTo(b.key));
    for (final row in rows.take(rows.length - maxEvidence)) {
      await _state.removeIfPresent(row.key);
    }
  }
}
