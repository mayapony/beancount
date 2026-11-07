library;

import '../../data/db/app_database.dart';
import '../../data/repositories/app_state_repository.dart';
import 'capture_diagnostics.dart';
import 'capture_evidence.dart';
import 'capture_rule.dart';
import 'capture_rule_generator.dart';
import 'capture_rule_verification.dart';
import 'capture_surface.dart';
import 'capture_tree.dart';

/// 自愈规则学习：消费留证 → 云端生成受限 DSL 规则 → 回放验证 → 入库。
///
/// - 通过验证：升灰度（grey，可自动入账），替换同 surface 旧规则；
/// - 未通过：标待定（pending，不自动入账），用户下次仍需截图；
/// - surface 已标记「截图优先」（树读不出）：跳过，不反复生成；
/// - 云端未配置：跳过，不上传。
class CaptureRuleLearner {
  CaptureRuleLearner({
    required this.db,
    required this.generator,
    required this.isConfigured,
    this.diag,
    void Function(String)? log,
  }) : _log = log;

  final AppDatabase db;
  final CaptureRuleGenerator generator;
  final Future<bool> Function() isConfigured;

  /// 运行记录出口；为 null 时只跳过记录。
  final CaptureDiagnostics? diag;

  final void Function(String)? _log;

  CaptureRuleStore get _rules => CaptureRuleStore(AppStateRepository(db));
  CaptureEvidenceStore get _evidence => CaptureEvidenceStore(AppStateRepository(db));
  CaptureSurfaceStore get _surfaces => CaptureSurfaceStore(AppStateRepository(db));

  /// 消费全部留证；处理过的证据（无论成败）都移除，避免反复重试。
  Future<void> learnAll() async {
    for (final evidence in await _evidence.readAll()) {
      await _learnOne(evidence);
      await _evidence.remove(evidence.id);
    }
  }

  Future<void> _learnOne(CaptureEvidence evidence) async {
    // 无障碍规则：从控件树学（树读不出就跳过或标记截图优先）。
    await _learnForTarget(
      evidence,
      target: RuleTarget.accessibility,
      source: evidence.dump,
      fingerprint: evidence.surfaceFingerprint,
    );

    // 通知规则：从通知文本学（留证时抓到了通知才学）。
    final notificationText = evidence.notificationText?.trim();
    if (notificationText != null && notificationText.isNotEmpty) {
      await _learnForTarget(
        evidence,
        target: RuleTarget.notification,
        source: notificationText,
        fingerprint: null,
      );
    }
  }

  Future<void> _learnForTarget(
    CaptureEvidence evidence, {
    required RuleTarget target,
    required String source,
    required String? fingerprint,
  }) async {
    if (source.trim().isEmpty) return;

    // 无障碍规则：树读不出内容时学不出金额，直接跳过。
    if (target == RuleTarget.accessibility &&
        isTreeUnreadable(dumpToTree(source))) {
      _log?.call('learner: skip accessibility (unreadable tree) pkg=${evidence.packageName}');
      await _skip(evidence, target: target, reason: 'empty_tree');
      return;
    }

    // 通知规则：只有通知文本里真能找到这笔金额，才拿它生成规则；否则宁可跳过，
    // 也不要拿一条无关的聊天通知去编一个「抓任意数字」的正则。
    if (target == RuleTarget.notification &&
        !_notificationCarriesAmount(source, evidence.amountCents)) {
      _log?.call('learner: skip notification (no matching amount) pkg=${evidence.packageName}');
      await _skip(evidence, target: target, reason: 'no_matching_notification');
      return;
    }

    // 截图优先的 surface（树读不出）不再尝试生成无障碍规则。
    if (target == RuleTarget.accessibility &&
        fingerprint != null &&
        await _surfaces.isMarked(evidence.packageName, fingerprint)) {
      _log?.call('learner: skip (screenshot-first) pkg=${evidence.packageName}');
      await _skip(evidence, target: target, reason: 'screenshot_first');
      return;
    }

    final desensitized = target == RuleTarget.accessibility
        ? desensitizeTree(dumpToTree(source))
        : desensitizeText(source);

    final service = RuleGenerationService(
      generator: generator,
      isConfigured: isConfigured,
    );
    final rule = await service.generate(CaptureRuleGenerationRequest(
      packageName: evidence.packageName,
      target: target,
      direction: evidence.direction,
      desensitizedTree: desensitized,
      amountCents: evidence.amountCents,
      surfaceFingerprint: fingerprint,
    ));
    if (rule == null) {
      _log?.call('learner: unconfigured pkg=${evidence.packageName} target=${target.name}');
      await _skip(evidence, target: target, reason: 'unconfigured');
      return;
    }

    // 锚点自检：先确认规则说清了「哪一行是金额」，再做回放验证。
    final problem = anchorProblem(rule, source: source);
    if (problem != null) {
      _log?.call(
        'learner: rule=${rule.id} unanchored problem=$problem '
        'strategy=${rule.amountStrategy.name} label=${rule.adjacentLabel} '
        'pattern=${rule.amountPattern}',
      );
      await diag?.record(
        kind: CaptureDiagKind.llmRuleGen,
        packageName: evidence.packageName,
        target: target.name,
        ok: false,
        reason: 'unanchored',
        detail: {
          'rule': rule.id,
          'problem': problem,
          'strategy': rule.amountStrategy.name,
          'label': rule.adjacentLabel,
          'pattern': rule.amountPattern,
        },
      );
      await _upsert(rule);
      return;
    }

    // 回放验证：正例必须解出当次真值金额。
    final sample = target == RuleTarget.accessibility
        ? RuleReplaySample(
            tree: dumpToTree(source),
            expectedAmountCents: evidence.amountCents,
          )
        : RuleReplaySample(
            text: source,
            expectedAmountCents: evidence.amountCents,
          );
    final verified = verifyRule(rule, [sample]);
    _log?.call(
      'learner: rule=${rule.id} target=${target.name} verified=$verified '
      'strategy=${rule.amountStrategy.name} label=${rule.adjacentLabel} '
      'pattern=${rule.amountPattern} truth=${evidence.amountCents} '
      'source=[${source.replaceAll('\n', ' | ').replaceAll(RegExp(r'\s+'), ' ')}]',
    );
    final applied = verified ? RuleTrustLadder.activateGrey(rule) : rule;
    await diag?.record(
      kind: CaptureDiagKind.llmRuleGen,
      packageName: evidence.packageName,
      target: target.name,
      ok: verified,
      reason: verified ? 'verified' : 'rejected',
      detail: {
        'rule': rule.id,
        'verified': verified,
        'tier': applied.tier.name,
        'fingerprint': fingerprint,
        'truth_cents': evidence.amountCents,
      },
    );
    await _upsert(applied);
  }

  /// 通知文本里能不能找到这笔金额（「¥12.00」「12.00」「12」都算）。
  static bool _notificationCarriesAmount(String text, int amountCents) {
    final yuan = amountCents ~/ 100;
    final cents = (amountCents % 100).toString().padLeft(2, '0');
    final candidates = <String>{
      '$yuan.$cents',
      if (amountCents % 100 == 0) '$yuan',
    };
    return candidates.any(text.contains);
  }

  /// 学习被跳过时记下原因：跳过不等于没发生，用户需要知道这一笔为什么学不到规则。
  Future<void> _skip(
    CaptureEvidence evidence, {
    required RuleTarget target,
    required String reason,
  }) async {
    await diag?.record(
      kind: CaptureDiagKind.learnSkipped,
      packageName: evidence.packageName,
      target: target.name,
      ok: false,
      reason: reason,
      detail: {'evidence': evidence.id},
    );
  }

  /// 同 surface（包 + 目标 + 指纹）的旧规则替换，避免同页反复生成堆积。
  Future<void> _upsert(CaptureRule rule) async {
    final existing = await _rules.load();
    final kept = existing.where((r) => !_sameSurface(r, rule)).toList();
    await _rules.save([...kept, rule]);
  }

  bool _sameSurface(CaptureRule a, CaptureRule b) =>
      a.packageName == b.packageName &&
      a.target == b.target &&
      a.surfaceFingerprint == b.surfaceFingerprint;
}
