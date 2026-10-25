import 'package:bean_count/services/capture/capture_candidate.dart';
import 'package:bean_count/services/capture/capture_rule.dart';
import 'package:bean_count/services/capture/capture_rule_generator.dart';
import 'package:bean_count/services/capture/capture_tree.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final request = CaptureRuleGenerationRequest(
    packageName: 'com.tencent.mm',
    target: RuleTarget.accessibility,
    direction: CaptureDirection.expense,
    desensitizedTree: 'View|支付成功\n  TextView|¥##.##',
    amountCents: 1250,
    surfaceFingerprint: 'fp-abc',
  );

  group('RuleGenerationService', () {
    test('配置后调用生成器', () async {
      final fake = _FakeGenerator();
      final service = RuleGenerationService(
        generator: fake,
        isConfigured: () async => true,
      );

      final rule = await service.generate(request);

      expect(rule, isNotNull);
      expect(fake.calls, 1);
      expect(rule!.packageName, 'com.tencent.mm');
      expect(rule.surfaceFingerprint, 'fp-abc');
    });

    test('未配置跳过且不调用', () async {
      final fake = _FakeGenerator();
      final service = RuleGenerationService(
        generator: fake,
        isConfigured: () async => false,
      );

      final rule = await service.generate(request);

      expect(rule, isNull);
      expect(fake.calls, 0);
    });
  });

  group('desensitizeTree', () {
    test('掩掉所有数字，保留结构与标签', () {
      final tree = CaptureNode(className: 'View', text: '支付成功', children: [
        CaptureNode(className: 'TextView', text: '¥12.50'),
        CaptureNode(className: 'TextView', text: '订单 202610251234'),
      ]);

      final dump = desensitizeTree(tree);

      expect(dump, contains('支付成功'));
      expect(dump, contains('¥##.##'));
      expect(dump, contains('订单 ############'));
      expect(dump, isNot(contains('12.50')));
      expect(dump, isNot(contains('202610251234')));
    });
  });
}

class _FakeGenerator implements CaptureRuleGenerator {
  int calls = 0;

  @override
  Future<CaptureRule> generate(CaptureRuleGenerationRequest request) async {
    calls++;
    return CaptureRule(
      id: 'r',
      packageName: request.packageName,
      target: request.target,
      surfaceFingerprint: request.surfaceFingerprint,
    );
  }
}
