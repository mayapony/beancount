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
      strategy: AmountStrategy.regex,
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
  group('排除词只看金额邻域', () {
    CaptureRule rule({List<String> exclude = const ['余额', '优惠', '券']}) =>
        CaptureRule(
          id: 'r1',
          packageName: 'com.tencent.mm',
          target: RuleTarget.accessibility,
          amountStrategy: AmountStrategy.adjacentLabel,
          adjacentLabel: '实付金额',
          excludeKeywords: exclude,
          tier: CaptureRuleTier.grey,
        );

    CaptureNode treeOf(List<String> lines) {
      var dump = '';
      for (final line in lines) {
        dump += 'android.widget.TextView|$line\n';
      }
      return dumpToTree(dump);
    }

    test('页面别处出现促销词仍然抽得出金额', () {
      final tree = treeOf([
        'REDMI K90 Pro Max',
        '实付金额',
        '¥4199',
        '订单编号',
        '1266382316857929',
        '券｜下单享8.7折',
      ]);

      final attempt = const CaptureRuleExecutor().attempt(rule(), tree: tree);

      expect(attempt.extraction?.amountCents, 419900);
      expect(attempt.excludedKeyword, isNull);
    });

    test('金额相邻行出现排除词才判为排除', () {
      final tree = treeOf([
        '实付金额',
        '优惠后 ¥4199',
      ]);

      final attempt = const CaptureRuleExecutor().attempt(rule(), tree: tree);

      expect(attempt.extraction, isNull);
      expect(attempt.excludedKeyword, '优惠');
    });

    test('通知文本只有一段，等价于整段匹配', () {
      final notificationRule = CaptureRule(
        id: 'n1',
        packageName: 'com.tencent.mm',
        target: RuleTarget.notification,
        amountStrategy: AmountStrategy.regex,
        amountPattern: r'¥(\d+(?:\.\d{1,2})?)',
        excludeKeywords: const ['余额'],
        tier: CaptureRuleTier.active,
      );

      final attempt = const CaptureRuleExecutor()
          .attempt(notificationRule, text: '余额变动 支出 ¥12.00');

      expect(attempt.extraction, isNull);
      expect(attempt.excludedKeyword, '余额');
    });
  });
}