import 'package:bean_count/services/capture/capture_candidate.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('CaptureCandidate', () {
    test('字段齐全且 hasAmount 判定正确', () {
      final at = DateTime(2026, 10, 25, 12, 0);
      final candidate = CaptureCandidate(
        source: CaptureSource.notification,
        direction: CaptureDirection.expense,
        packageName: 'com.tencent.mm',
        amountCents: 1250,
        note: '满巍明生炸鸡架',
        happenedAt: at,
        rawText: '微信支付 ¥12.50',
        surfaceFingerprint: null,
      );

      expect(candidate.source, CaptureSource.notification);
      expect(candidate.direction, CaptureDirection.expense);
      expect(candidate.packageName, 'com.tencent.mm');
      expect(candidate.amountCents, 1250);
      expect(candidate.note, '满巍明生炸鸡架');
      expect(candidate.happenedAt, at);
      expect(candidate.rawText, '微信支付 ¥12.50');
      expect(candidate.surfaceFingerprint, isNull);
      expect(candidate.hasAmount, isTrue);
    });

    test('合并键：同包同金额一致', () {
      expect(
        _candidate().mergeKey,
        _candidate().mergeKey,
      );
      expect(_candidate().mergeKey, 'com.tencent.mm|1250');
    });

    test('合并键：不同金额或不同包不一致', () {
      expect(
        _candidate().mergeKey,
        isNot(_candidate(amount: 880).mergeKey),
      );
      expect(
        _candidate().mergeKey,
        isNot(
          _candidate(pkg: 'com.eg.android.AlipayGphone').mergeKey,
        ),
      );
    });

    test('合并键：无金额时为空', () {
      expect(_candidate(amount: null).mergeKey, isNull);
    });
  });
}

CaptureCandidate _candidate({
  int? amount = 1250,
  String pkg = 'com.tencent.mm',
}) {
  return CaptureCandidate(
    source: CaptureSource.accessibility,
    direction: CaptureDirection.expense,
    packageName: pkg,
    amountCents: amount,
  );
}
