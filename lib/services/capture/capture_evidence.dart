library;

import 'dart:convert';

import '../../data/repositories/app_state_repository.dart';
import 'capture_candidate.dart';

/// 一次截图兜底的留证：包名 + 指纹 + 控件树快照 + 当次入账真值金额。
///
/// 规则由它生成；`dump` 是原生侧环形缓冲里的树快照（缩进文本），生成与回放验证
/// 都从它还原树，不落整屏截图、不落 rawText。
class CaptureEvidence {
  const CaptureEvidence({
    required this.id,
    required this.packageName,
    required this.dump,
    required this.amountCents,
    required this.direction,
    this.surfaceFingerprint,
    this.createdAt,
  });

  final String id;
  final String packageName;
  final String dump;
  final int amountCents;
  final CaptureDirection direction;
  final String? surfaceFingerprint;
  final DateTime? createdAt;

  Map<String, dynamic> toJson() => {
        'id': id,
        'package_name': packageName,
        'dump': dump,
        'amount_cents': amountCents,
        'direction': direction.name,
        if (surfaceFingerprint != null) 'surface_fingerprint': surfaceFingerprint,
        if (createdAt != null) 'created_at': createdAt!.toUtc().toIso8601String(),
      };

  static CaptureEvidence? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final id = raw['id'];
    final packageName = raw['package_name'];
    final dump = raw['dump'];
    final amountCents = raw['amount_cents'];
    if (id is! String ||
        packageName is! String ||
        dump is! String ||
        amountCents is! int) {
      return null;
    }
    return CaptureEvidence(
      id: id,
      packageName: packageName,
      dump: dump,
      amountCents: amountCents,
      direction: _direction(raw['direction']),
      surfaceFingerprint: raw['surface_fingerprint']?.toString(),
      createdAt: DateTime.tryParse(raw['created_at']?.toString() ?? ''),
    );
  }

  static CaptureDirection _direction(Object? raw) {
    for (final value in CaptureDirection.values) {
      if (value.name == raw?.toString()) return value;
    }
    return CaptureDirection.expense;
  }
}

/// 留证的读写：独立 key 落 `app_state`，规则学习引擎逐条消费。
class CaptureEvidenceStore {
  CaptureEvidenceStore(this._state);

  final AppStateRepository _state;

  static const kPrefix = 'capture_evidence:';
  static const kMaxEntries = 20;

  Future<void> add(CaptureEvidence evidence) async {
    await _state.write(
      '$kPrefix${evidence.id}',
      jsonEncode(evidence.toJson()),
    );
    await _prune();
  }

  Future<List<CaptureEvidence>> readAll() async {
    final rows = await _state.readStartingWith(kPrefix);
    final evidence = <CaptureEvidence>[];
    for (final row in rows) {
      final item = _decode(row.value);
      if (item != null) evidence.add(item);
    }
    evidence.sort((a, b) {
      final aTime = a.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
      final bTime = b.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
      return aTime.compareTo(bTime);
    });
    return evidence;
  }

  Future<void> remove(String id) async {
    await _state.remove('$kPrefix$id');
  }

  Future<void> _prune() async {
    final rows = await _state.readStartingWith(kPrefix);
    if (rows.length <= kMaxEntries) return;
    final excess = rows.length - kMaxEntries;
    rows.sort((a, b) => a.key.compareTo(b.key));
    for (final row in rows.take(excess)) {
      await _state.removeIfPresent(row.key);
    }
  }

  static CaptureEvidence? _decode(String? raw) {
    if (raw == null || raw.trim().isEmpty) return null;
    try {
      return CaptureEvidence.fromJson(jsonDecode(raw));
    } on FormatException {
      return null;
    }
  }
}
