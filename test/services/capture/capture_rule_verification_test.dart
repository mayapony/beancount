import 'package:bean_count/services/capture/capture_candidate.dart';
import 'package:bean_count/services/capture/capture_rule.dart';
import 'package:bean_count/services/capture/capture_rule_verification.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final regexRule = CaptureRule(
    id: 'r',
    packageName: 'com.tencent.mm',
    target: RuleTarget.notification,
    direction: CaptureDirection.expense,
    amountStrategy: AmountStrategy.regex,
    amountPattern: r'支付\s*[¥￥]\s*(\d+(?:\.\d{1,2})?)',
  );

  group('verifyRule', () {
    test('正例解出真值 + 负例静默 → 通过', () {
      final samples = [
        const RuleReplaySample(text: '微信支付 ¥12.50', expectedAmountCents: 1250),
        const RuleReplaySample(text: '聊天消息，没有金额'),
      ];
      expect(verifyRule(regexRule, samples), isTrue);
    });

    test('正例解错金额 → 拒绝', () {
      final samples = [
        const RuleReplaySample(text: '微信支付 ¥12.50', expectedAmountCents: 999),
      ];
      expect(verifyRule(regexRule, samples), isFalse);
    });

    test('负例解出金额 → 拒绝', () {
      final maxRule = CaptureRule(
        id: 'r2',
        packageName: 'com.tencent.mm',
        target: RuleTarget.notification,
        amountStrategy: AmountStrategy.maxAmount,
      );
      final samples = [
        const RuleReplaySample(text: '余额 ¥1204.00'),
      ];
      expect(verifyRule(maxRule, samples), isFalse);
    });

    test('排除词让负例静默 → 通过', () {
      final maxRule = CaptureRule(
        id: 'r3',
        packageName: 'com.tencent.mm',
        target: RuleTarget.notification,
        amountStrategy: AmountStrategy.maxAmount,
        excludeKeywords: const ['余额'],
      );
      final samples = [
        const RuleReplaySample(text: '合计 ¥44.50', expectedAmountCents: 4450),
        const RuleReplaySample(text: '余额 ¥1204.00'),
      ];
      expect(verifyRule(maxRule, samples), isTrue);
    });
  });

  group('RuleTrustLadder', () {
    test('pending → grey → 确认 3 次 → active', () {
      var r = RuleTrustLadder.activateGrey(regexRule);
      expect(r.tier, CaptureRuleTier.grey);
      expect(r.confirmations, 0);

      r = RuleTrustLadder.confirm(r);
      r = RuleTrustLadder.confirm(r);
      expect(r.tier, CaptureRuleTier.grey);
      expect(r.confirmations, 2);

      r = RuleTrustLadder.confirm(r);
      expect(r.tier, CaptureRuleTier.active);
    });

    test('active 再确认保持 active', () {
      var r = RuleTrustLadder.activateGrey(regexRule);
      r = RuleTrustLadder.confirm(r);
      r = RuleTrustLadder.confirm(r);
      r = RuleTrustLadder.confirm(r);
      expect(r.tier, CaptureRuleTier.active);

      r = RuleTrustLadder.confirm(r);
      expect(r.tier, CaptureRuleTier.active);
    });

    test('改金额降回 grey 并清零', () {
      var r = RuleTrustLadder.activateGrey(regexRule);
      r = RuleTrustLadder.confirm(r);
      r = RuleTrustLadder.confirm(r);
      expect(r.confirmations, 2);

      r = RuleTrustLadder.demote(r);
      expect(r.tier, CaptureRuleTier.grey);
      expect(r.confirmations, 0);
    });
  });
}
