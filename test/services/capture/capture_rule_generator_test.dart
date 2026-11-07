import 'dart:convert';

import 'package:bean_count/data/db/app_database.dart';
import 'package:bean_count/data/db/connection.dart';
import 'package:bean_count/services/capture/capture_candidate.dart';
import 'package:bean_count/services/capture/capture_diagnostics.dart';
import 'package:bean_count/services/capture/capture_rule_generator_cloud.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:bean_count/services/capture/capture_rule.dart';
import 'package:bean_count/services/capture/capture_rule_generator.dart';
import 'package:bean_count/services/capture/capture_tree.dart';

void main() {
  group('CloudCaptureRuleGenerator 记录', cloudGeneratorTests);
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

  @override
  void close() {}
}

void cloudGeneratorTests() {
  late AppDatabase db;
  late CaptureDiagnostics diag;

  final request = CaptureRuleGenerationRequest(
    packageName: 'com.tencent.mm',
    target: RuleTarget.accessibility,
    direction: CaptureDirection.expense,
    desensitizedTree: 'View|支付成功\n  TextView|¥##.##',
    amountCents: 1250,
    surfaceFingerprint: 'fp-abc',
  );

  CloudCaptureRuleGenerator generator(MockClient client) =>
      CloudCaptureRuleGenerator(
        baseUrl: 'https://api.deepseek.com',
        model: 'deepseek-flash',
        apiKey: 'sk-test',
        client: client,
        diag: diag,
      );

  http.Response ok(String content) => http.Response.bytes(
        utf8.encode(jsonEncode({
          'choices': [
            {
              'message': {'role': 'assistant', 'content': content},
            },
          ],
        })),
        200,
        headers: {'content-type': 'application/json'},
      );

  setUp(() async {
    db = AppDatabase(openInMemoryConnection());
    diag = CaptureDiagnostics.forDatabase(db);
    await db.select(db.appState).get();
  });

  tearDown(() async => db.close());

  test('记下模型原文与实际入库的规则字段', () async {
    const content =
        '{"amount_strategy":"regex","amount_pattern":"¥(\\\\d+\\\\.\\\\d{2})",'
        '"direction":"expense","exclude_keywords":["余额"]}';
    final rule =
        await generator(MockClient((_) async => ok(content))).generate(request);

    final event = (await diag.events()).single;
    expect(event.kind, CaptureDiagKind.llmRuleGen);
    expect(event.reason, 'generated');
    expect(event.detail['rule'], rule.id);
    expect(event.detail['fingerprint'], 'fp-abc');
    expect(event.detail['truth_cents'], 1250);
    expect(event.detail['exclude_keywords'], contains('余额'));
    expect(await diag.evidence.read(event.evidenceId!),
        contains('amount_strategy'));
  });

  test('规则生成失败不留下半条记录', () async {
    final failing =
        generator(MockClient((_) async => http.Response('boom', 500)));

    await expectLater(
        failing.generate(request), throwsA(isA<RuleGenerationException>()));
    expect(await diag.events(), isEmpty);
  });

}
