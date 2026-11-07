import 'package:bean_count/services/capture/capture_candidate.dart';
import 'package:bean_count/services/capture/capture_diag_export.dart';
import 'package:bean_count/services/capture/capture_diagnostics.dart';
import 'package:bean_count/services/capture/capture_rule.dart';
import 'package:bean_count/services/capture/capture_settings.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final now = DateTime(2026, 11, 7, 18, 50);

  CaptureRule rule({String fingerprint = 'a1b2c3d4'}) => CaptureRule(
        id: 'r1',
        packageName: 'com.tencent.mm',
        target: RuleTarget.accessibility,
        surfaceFingerprint: fingerprint,
        direction: CaptureDirection.expense,
        amountStrategy: AmountStrategy.regex,
        amountPattern: r'¥(\d+(?:\.\d{1,2})?)',
        tier: CaptureRuleTier.grey,
      );

  test('报告包含状态、规则与事件', () {
    final report = buildCaptureDiagExport(
      settings: const CaptureSettings(enabled: true),
      rules: [rule()],
      events: [
        CaptureDiagEvent(
          seq: 1,
          at: now,
          kind: CaptureDiagKind.noRule,
          packageName: 'com.tencent.mm',
          ok: false,
          reason: 'no_rule',
          detail: const {'fingerprint': 'a1b2c3d4'},
        ),
      ],
      now: now,
    );

    expect(report, contains('自动记账: 已开启'));
    expect(report, contains('[规则] 1 条'));
    expect(report, contains('grey com.tencent.mm accessibility'));
    expect(report, contains('no_rule com.tencent.mm'));
    expect(report, contains('fingerprint: a1b2c3d4'));
  });

  test('规则为空时明确说明不会触发', () {
    final report = buildCaptureDiagExport(
      settings: const CaptureSettings(enabled: true),
      rules: const [],
      events: const [],
      now: now,
    );

    expect(report, contains('没有任何提取规则'));
  });

  test('抹掉商户名与 6 位以上数字，保留金额与指纹', () {
    final report = buildCaptureDiagExport(
      settings: const CaptureSettings(enabled: true),
      rules: [
        // 全数字指纹也必须原样保留
        rule(fingerprint: '12345678'),
      ],
      events: [
        CaptureDiagEvent(
          seq: 1,
          at: now,
          kind: CaptureDiagKind.llmRecognize,
          ok: true,
          detail: const {
            'model_fields': {
              'amount_cents': 1800,
              'merchant': '臻汁煌（金山软件园店）',
            },
            'order_no': '2026102512345678',
          },
        ),
      ],
      now: now,
    );

    expect(report, isNot(contains('臻汁煌')));
    expect(report, contains('merchant: ######'));
    expect(report, isNot(contains('2026102512345678')));
    expect(report, contains('1800'));
    expect(report, contains('12345678'));
  });

  test('脱敏后金额文本保持可读', () {
    final redacted = redactDiagText('收到 ¥12.34，订单 20261025123456');
    expect(redacted, contains('¥12.34'));
    expect(redacted, isNot(contains('20261025123456')));
  });

  test('证据随事件一起导出，被淘汰的显示已淘汰', () {
    final report = buildCaptureDiagExport(
      settings: const CaptureSettings(enabled: true),
      rules: const [],
      events: [
        CaptureDiagEvent(
          seq: 2,
          at: now,
          kind: CaptureDiagKind.treeCaptured,
          evidenceId: 'ev-1',
        ),
        CaptureDiagEvent(
          seq: 1,
          at: now.subtract(const Duration(seconds: 5)),
          kind: CaptureDiagKind.treeCaptured,
          evidenceId: 'ev-gone',
        ),
      ],
      evidence: const {'ev-1': 'View|支付成功'},
      now: now,
    );

    expect(report, contains('View|支付成功'));
    expect(report, contains('evidence: （已淘汰）'));
  });
}
