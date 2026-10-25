import 'package:bean_count/services/capture/capture_candidate.dart';
import 'package:bean_count/services/capture/capture_rule.dart';
import 'package:bean_count/services/capture/capture_rule_executor.dart';
import 'package:bean_count/services/capture/capture_tree.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const executor = CaptureRuleExecutor();

  CaptureRule rule({
    String id = 'r1',
    String pkg = 'com.tencent.mm',
    RuleTarget target = RuleTarget.notification,
    AmountStrategy strategy = AmountStrategy.regex,
    String? pattern,
    String? label,
    List<String> exclude = const [],
    CaptureDirection direction = CaptureDirection.expense,
  }) {
    return CaptureRule(
      id: id,
      packageName: pkg,
      target: target,
      amountStrategy: strategy,
      amountPattern: pattern,
      adjacentLabel: label,
      excludeKeywords: exclude,
      direction: direction,
    );
  }

  test('regex 策略从通知文本提取', () {
    final r = rule(pattern: r'支付\s*[¥￥]\s*(\d+(?:\.\d{1,2})?)');
    final result = executor.apply(r, text: '微信支付 ¥12.50');
    expect(result!.amountCents, 1250);
    expect(result.direction, CaptureDirection.expense);
  });

  test('maxAmount 策略取最大金额', () {
    final r = rule(
      target: RuleTarget.accessibility,
      strategy: AmountStrategy.maxAmount,
    );
    final tree = CaptureNode(children: [
      const CaptureNode(text: '¥6.00'),
      const CaptureNode(text: '合计 ¥44.50'),
    ]);
    final result = executor.apply(r, tree: tree);
    expect(result!.amountCents, 4450);
  });

  test('adjacentLabel 策略从标签邻近行取金额', () {
    final r = rule(
      target: RuleTarget.accessibility,
      strategy: AmountStrategy.adjacentLabel,
      label: '支付金额',
    );
    final tree = CaptureNode(children: [
      const CaptureNode(text: '支付金额'),
      const CaptureNode(text: '¥88.00'),
    ]);
    final result = executor.apply(r, tree: tree);
    expect(result!.amountCents, 8800);
  });

  test('排除词命中返回空', () {
    final r = rule(
      strategy: AmountStrategy.maxAmount,
      exclude: ['余额'],
    );
    expect(executor.apply(r, text: '余额 ¥1204.00'), isNull);
  });

  test('无匹配返回空', () {
    final r = rule(pattern: r'支付\s*[¥￥]\s*(\d+)');
    expect(executor.apply(r, text: '没有金额'), isNull);
  });

  test('方向随规则透传', () {
    final r = rule(
      pattern: r'退款\s*[¥￥]\s*(\d+)',
      direction: CaptureDirection.refund,
    );
    final result = executor.apply(r, text: '退款 ¥50');
    expect(result!.direction, CaptureDirection.refund);
  });
}
