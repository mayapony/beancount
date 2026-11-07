library;

import 'capture_rule.dart';
import 'capture_rule_executor.dart';
import 'capture_tree.dart';

/// 回放样本：正例带真值金额（规则应解出它），负例为 null（规则应静默）。
class RuleReplaySample {
  const RuleReplaySample({
    this.tree,
    this.text,
    this.expectedAmountCents,
  });

  final CaptureNode? tree;
  final String? text;
  final int? expectedAmountCents;

  bool get isPositive => expectedAmountCents != null;
}

/// 回放验证：正例必须解出真值，负例必须静默，全部通过才算有效。
///
/// 一条「能匹配但匹配错」的规则比不匹配更糟——它会关掉「没记上」的告警。
/// 所以入库前用它挡一道：对不上真值、或在别页乱吐金额的规则一律不生效。
bool verifyRule(CaptureRule rule, Iterable<RuleReplaySample> samples) {
  const executor = CaptureRuleExecutor();
  for (final sample in samples) {
    final extraction = executor.apply(rule, tree: sample.tree, text: sample.text);
    if (sample.isPositive) {
      if (extraction == null ||
          extraction.amountCents != sample.expectedAmountCents) {
        return false;
      }
    } else if (extraction != null) {
      return false;
    }
  }
  return true;
}

/// 信任阶梯：pending → grey（验证通过）→ active（灰度确认满 3 次）；
/// 任一次用户改了金额就降回 grey、计数清零。
class RuleTrustLadder {
  RuleTrustLadder._();

  static const greyConfirmationsToActivate = 3;

  /// 回放验证通过后，从 pending 进入灰度。
  static CaptureRule activateGrey(CaptureRule rule) =>
      rule.copyWith(tier: CaptureRuleTier.grey, confirmations: 0);

  /// 灰度阶段用户原样确认一次；累计满 3 次升 active。
  static CaptureRule confirm(CaptureRule rule) {
    if (rule.tier == CaptureRuleTier.active) return rule;
    final next = rule.confirmations + 1;
    return rule.copyWith(
      tier: next >= greyConfirmationsToActivate
          ? CaptureRuleTier.active
          : CaptureRuleTier.grey,
      confirmations: next,
    );
  }

  /// 用户改了金额 → 降回灰度、计数清零。
  static CaptureRule demote(CaptureRule rule) =>
      rule.copyWith(tier: CaptureRuleTier.grey, confirmations: 0);
}
/// 锚点自检：规则能不能说清「哪一行是金额」。
///
/// 回放验证只能证明「这一次解对了」，证明不了「换一笔还对」。这里的自检专挡
/// 两类看似通过、实则随便抓的规则：
/// - 相邻标签在页面原文里根本不存在（模型改写了标签文字）；
/// - regex 在同一页命中多个不同金额（说明它只会抓第一个数字，比如把原价当实付）。
String? anchorProblem(CaptureRule rule, {required String source}) {
  switch (rule.amountStrategy) {
    case AmountStrategy.adjacentLabel:
      final label = rule.adjacentLabel?.trim();
      if (label == null || label.isEmpty) return 'no_label';
      if (!source.contains(label)) return 'label_not_found';
      return null;
    case AmountStrategy.regex:
      final pattern = rule.amountPattern;
      if (pattern == null || pattern.isEmpty) return 'no_pattern';
      final amounts =
          const CaptureRuleExecutor().distinctRegexAmounts(pattern, source);
      if (amounts.length > 1) return 'ambiguous_regex';
      return null;
  }
}