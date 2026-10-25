library;

import 'dart:convert';

import '../../data/repositories/app_state_repository.dart';
import 'capture_candidate.dart';

/// 规则目标：作用于无障碍控件树，还是通知文本。
enum RuleTarget { accessibility, notification }

/// 金额抽取策略：LLM 从这几个原语里选并参数化，运行时由执行器套用。
enum AmountStrategy { regex, adjacentLabel }

/// 信任阶梯：pending 待验证 → grey 灰度 → active 自动。
enum CaptureRuleTier { pending, grey, active }

/// 一条提取规则（LLM 生成的受限 DSL）。
///
/// 只表达「在哪抽、怎么抽、方向、排除词」，不含可执行代码；规则文件可热更、
/// 可 diff、可回滚，也没有远程代码执行面。
class CaptureRule {
  const CaptureRule({
    required this.id,
    required this.packageName,
    required this.target,
    this.surfaceFingerprint,
    this.direction = CaptureDirection.expense,
    this.amountStrategy = AmountStrategy.regex,
    this.amountPattern,
    this.adjacentLabel,
    this.excludeKeywords = const [],
    this.version = 1,
    this.tier = CaptureRuleTier.pending,
    this.confirmations = 0,
    this.createdAt,
    this.updatedAt,
  });

  final String id;
  final String packageName;
  final RuleTarget target;

  /// 无障碍目标时用于匹配页面；通知目标时为 null。
  final String? surfaceFingerprint;

  final CaptureDirection direction;
  final AmountStrategy amountStrategy;

  /// regex 策略的正则（LLM 生成）。
  final String? amountPattern;

  /// adjacentLabel 策略的邻近标签（LLM 生成）。
  final String? adjacentLabel;

  /// 排除词（LLM 生成）：命中的金额不当支付。
  final List<String> excludeKeywords;

  final int version;
  final CaptureRuleTier tier;
  final int confirmations;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  Map<String, dynamic> toJson() => {
        'id': id,
        'package_name': packageName,
        'target': target.name,
        if (surfaceFingerprint != null) 'surface_fingerprint': surfaceFingerprint,
        'direction': direction.name,
        'amount_strategy': amountStrategy.name,
        if (amountPattern != null) 'amount_pattern': amountPattern,
        if (adjacentLabel != null) 'adjacent_label': adjacentLabel,
        'exclude_keywords': excludeKeywords,
        'version': version,
        'tier': tier.name,
        'confirmations': confirmations,
        if (createdAt != null) 'created_at': createdAt!.toUtc().toIso8601String(),
        if (updatedAt != null) 'updated_at': updatedAt!.toUtc().toIso8601String(),
      };

  static CaptureRule? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final id = raw['id'];
    final packageName = raw['package_name'];
    if (id is! String || packageName is! String) return null;
    final target = _enumByName(RuleTarget.values, raw['target']);
    if (target == null) return null;
    return CaptureRule(
      id: id,
      packageName: packageName,
      target: target,
      surfaceFingerprint: raw['surface_fingerprint']?.toString(),
      direction:
          _enumByName(CaptureDirection.values, raw['direction']) ??
              CaptureDirection.expense,
      amountStrategy:
          _enumByName(AmountStrategy.values, raw['amount_strategy']) ??
              AmountStrategy.regex,
      amountPattern: raw['amount_pattern']?.toString(),
      adjacentLabel: raw['adjacent_label']?.toString(),
      excludeKeywords: raw['exclude_keywords'] is List
          ? (raw['exclude_keywords'] as List)
              .whereType<String>()
              .toList(growable: false)
          : const [],
      version: raw['version'] is int ? raw['version'] as int : 1,
      tier: _enumByName(CaptureRuleTier.values, raw['tier']) ??
          CaptureRuleTier.pending,
      confirmations:
          raw['confirmations'] is int ? raw['confirmations'] as int : 0,
      createdAt: DateTime.tryParse(raw['created_at']?.toString() ?? ''),
      updatedAt: DateTime.tryParse(raw['updated_at']?.toString() ?? ''),
    );
  }

  CaptureRule copyWith({
    CaptureDirection? direction,
    AmountStrategy? amountStrategy,
    String? amountPattern,
    String? adjacentLabel,
    List<String>? excludeKeywords,
    int? version,
    CaptureRuleTier? tier,
    int? confirmations,
    DateTime? updatedAt,
  }) {
    return CaptureRule(
      id: id,
      packageName: packageName,
      target: target,
      surfaceFingerprint: surfaceFingerprint,
      direction: direction ?? this.direction,
      amountStrategy: amountStrategy ?? this.amountStrategy,
      amountPattern: amountPattern ?? this.amountPattern,
      adjacentLabel: adjacentLabel ?? this.adjacentLabel,
      excludeKeywords: excludeKeywords ?? this.excludeKeywords,
      version: version ?? this.version,
      tier: tier ?? this.tier,
      confirmations: confirmations ?? this.confirmations,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}

T? _enumByName<T extends Enum>(List<T> values, Object? raw) {
  final name = raw?.toString();
  if (name == null) return null;
  for (final value in values) {
    if (value.name == name) return value;
  }
  return null;
}

/// 规则库的读写：版本化 JSON + last-known-good 回滚。
///
/// 存 `app_state`：当前规则一个 key、上一版（LKG）一个 key、数字版本一个 key。
/// 每次保存把当前挪到 LKG、再写新规则并递增版本；出问题可回滚到上一版。
class CaptureRuleStore {
  CaptureRuleStore(this._state);

  final AppStateRepository _state;

  static const kRulesKey = 'capture_rules';
  static const kLkgKey = 'capture_rules_lkg';
  static const kVersionKey = 'capture_rules_version';

  Future<List<CaptureRule>> load() async =>
      _decodeList(await _state.read(kRulesKey));

  /// 保存整份规则并返回新版本号。
  Future<int> save(List<CaptureRule> rules) async {
    final current = await _state.read(kRulesKey);
    if (current != null && current.trim().isNotEmpty) {
      await _state.write(kLkgKey, current);
    }
    await _state.write(
      kRulesKey,
      jsonEncode([for (final rule in rules) rule.toJson()]),
    );
    final version = (await currentVersion()) + 1;
    await _state.write(kVersionKey, '$version');
    return version;
  }

  Future<int> currentVersion() async =>
      int.tryParse(await _state.read(kVersionKey) ?? '') ?? 0;

  /// 回滚到上一版（LKG）；没有上一版时返回 null。
  Future<List<CaptureRule>?> rollback() async {
    final lkg = await _state.read(kLkgKey);
    if (lkg == null || lkg.trim().isEmpty) return null;
    await _state.write(kRulesKey, lkg);
    final version = (await currentVersion()) + 1;
    await _state.write(kVersionKey, '$version');
    return _decodeList(lkg);
  }

  List<CaptureRule> _decodeList(String? raw) {
    if (raw == null || raw.trim().isEmpty) return const [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const [];
      return [
        for (final item in decoded)
          if (CaptureRule.fromJson(item) case final rule?) rule,
      ];
    } on FormatException {
      return const [];
    }
  }
}
