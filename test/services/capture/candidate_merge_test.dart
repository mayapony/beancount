import 'package:bean_count/services/capture/candidate_merge.dart';
import 'package:bean_count/services/capture/capture_candidate.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final base = DateTime(2026, 10, 25, 12, 0, 0);

  CaptureCandidate c({
    int? amount = 1250,
    String pkg = 'com.tencent.mm',
    DateTime? at,
  }) {
    return CaptureCandidate(
      source: CaptureSource.notification,
      direction: CaptureDirection.expense,
      packageName: pkg,
      amountCents: amount,
      happenedAt: at,
    );
  }

  test('同包同金额、时间在窗口内合并为一条', () {
    final result = mergeCandidates([
      c(at: base),
      c(at: base.add(const Duration(seconds: 60))),
    ]);
    expect(result, hasLength(1));
  });

  test('同包同金额、时间超过窗口保留两条', () {
    final result = mergeCandidates([
      c(at: base),
      c(at: base.add(const Duration(seconds: 180))),
    ]);
    expect(result, hasLength(2));
  });

  test('不同金额或不同包不合并', () {
    final result = mergeCandidates([
      c(at: base),
      c(amount: 880, at: base),
      c(pkg: 'com.eg.android.AlipayGphone', at: base),
    ]);
    expect(result, hasLength(3));
  });

  test('无金额的候选原样保留、不参与合并', () {
    final result = mergeCandidates([
      c(amount: null, at: base),
      c(amount: null, at: base),
    ]);
    expect(result, hasLength(2));
  });

  test('无时间的候选原样保留、不参与合并', () {
    final result = mergeCandidates([
      c(at: base),
      c(at: null),
    ]);
    expect(result, hasLength(2));
  });
}
