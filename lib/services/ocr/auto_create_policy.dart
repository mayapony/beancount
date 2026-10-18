import 'dart:convert';

import '../../data/repositories/app_state_repository.dart';

/// 为什么没允许自动新建。
enum AutoCreateBlocked { disabled, perEntry, weekly, total }

/// 配额判定结果。
class AutoCreateDecision {
  const AutoCreateDecision._(this.allowed, this.blocked);

  const AutoCreateDecision.allow() : this._(true, null);
  const AutoCreateDecision.deny(AutoCreateBlocked reason) : this._(false, reason);

  final bool allowed;
  final AutoCreateBlocked? blocked;
}

/// 自动新建分类 / 标签的配额闸门。
///
/// 只读 `app_state` 里的创建时间戳，**不写任何账本数据**；真正落库由保存流程在
/// 用户点「完成」后调用。这样识别、取消、重开面板都不会留下副作用。
///
/// 规则（与 spec 对齐）：
/// - 单笔：分类 ≤1、标签 ≤2
/// - 滚动 7 天：分类 ≤3、标签 ≤10
/// - 分类总数上限 40
/// - 开关关闭时一律不建
class AutoCreatePolicy {
  AutoCreatePolicy(this._state, {DateTime Function()? now})
      : _now = now ?? DateTime.now;

  final AppStateRepository _state;
  final DateTime Function() _now;

  static const kCategoryLogKey = 'auto_create_category_log';
  static const kTagLogKey = 'auto_create_tag_log';

  static const kWeeklyWindow = Duration(days: 7);
  static const kCategoryPerEntryLimit = 1;
  static const kTagPerEntryLimit = 2;
  static const kCategoryWeeklyLimit = 3;
  static const kTagWeeklyLimit = 10;
  static const kCategoryTotalLimit = 40;

  /// 分类能否新建：`requested` 是这一笔想新建的数量。
  Future<AutoCreateDecision> checkCategory({
    required bool enabled,
    required int categoryTotal,
    int requested = 1,
  }) async {
    if (!enabled) return const AutoCreateDecision.deny(AutoCreateBlocked.disabled);
    if (requested > kCategoryPerEntryLimit) {
      return const AutoCreateDecision.deny(AutoCreateBlocked.perEntry);
    }
    if (categoryTotal >= kCategoryTotalLimit) {
      return const AutoCreateDecision.deny(AutoCreateBlocked.total);
    }
    final recent = await _recent(kCategoryLogKey);
    if (recent.length + requested > kCategoryWeeklyLimit) {
      return const AutoCreateDecision.deny(AutoCreateBlocked.weekly);
    }
    return const AutoCreateDecision.allow();
  }

  /// 标签能否新建：`requested` 是这一笔想新建的数量。
  Future<AutoCreateDecision> checkTag({
    required bool enabled,
    int requested = 1,
  }) async {
    if (!enabled) return const AutoCreateDecision.deny(AutoCreateBlocked.disabled);
    if (requested > kTagPerEntryLimit) {
      return const AutoCreateDecision.deny(AutoCreateBlocked.perEntry);
    }
    final recent = await _recent(kTagLogKey);
    if (recent.length + requested > kTagWeeklyLimit) {
      return const AutoCreateDecision.deny(AutoCreateBlocked.weekly);
    }
    return const AutoCreateDecision.allow();
  }

  /// 记录一次分类创建（保存成功后调用）。
  Future<void> markCategoryCreated() => _append(kCategoryLogKey);

  /// 记录一次标签创建（保存成功后调用）。
  Future<void> markTagCreated() => _append(kTagLogKey);

  Future<List<DateTime>> _recent(String key) async {
    final raw = await _state.read(key);
    if (raw == null || raw.trim().isEmpty) return const [];
    final cutoff = _now().subtract(kWeeklyWindow);
    final out = <DateTime>[];
    for (final value in _decode(raw)) {
      final at = DateTime.tryParse(value);
      if (at != null && at.isAfter(cutoff)) out.add(at);
    }
    return out;
  }

  Future<void> _append(String key) async {
    final current = _decode(await _state.read(key));
    final cutoff = _now().subtract(kWeeklyWindow);
    final kept = current.where((value) {
      final at = DateTime.tryParse(value);
      return at != null && at.isAfter(cutoff);
    }).toList();
    kept.add(_now().toUtc().toIso8601String());
    await _state.write(key, jsonEncode(kept));
  }

  List<String> _decode(String? raw) {
    if (raw == null || raw.trim().isEmpty) return const [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const [];
      return decoded.whereType<String>().toList();
    } on FormatException {
      // 数据坏了就当没有配额记录，不阻塞记账
      return const [];
    }
  }
}
