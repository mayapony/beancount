library;

import '../../data/db/app_database.dart';
import '../../data/repositories/app_state_repository.dart';
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
  });

  final AppDatabase db;
  final CaptureRuleGenerator generator;
  final Future<bool> Function() isConfigured;

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
    final fingerprint = evidence.surfaceFingerprint;
    if (fingerprint != null &&
        await _surfaces.isMarked(evidence.packageName, fingerprint)) {
      return;
    }

    final service = RuleGenerationService(
      generator: generator,
      isConfigured: isConfigured,
    );
    final rule = await service.generate(CaptureRuleGenerationRequest(
      packageName: evidence.packageName,
      target: RuleTarget.accessibility,
      direction: evidence.direction,
      desensitizedTree: desensitizeTree(dumpToTree(evidence.dump)),
      amountCents: evidence.amountCents,
      surfaceFingerprint: fingerprint,
    ));
    if (rule == null) return;

    // 回放验证：正例必须解出当次真值金额（负例在同包其它页面留证，见 8.x 扩展）。
    final verified = verifyRule(rule, [
      RuleReplaySample(
        tree: dumpToTree(evidence.dump),
        expectedAmountCents: evidence.amountCents,
      ),
    ]);
    await _upsert(verified ? RuleTrustLadder.activateGrey(rule) : rule);
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
