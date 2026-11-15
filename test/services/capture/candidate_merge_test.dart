import 'package:bean_count/services/capture/candidate_merge.dart';
import 'package:bean_count/services/capture/capture_candidate.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final base = DateTime(2026, 10, 25, 12, 0, 0);

  CaptureCandidate c({
    int? amount = 1250,
    String pkg = 'com.tencent.mm',
    DateTime? at,
    CaptureSource source = CaptureSource.notification,
  }) {
    return CaptureCandidate(
      source: source,
      direction: CaptureDirection.expense,
      packageName: pkg,
      amountCents: amount,
      happenedAt: at,
    );
  }

  CaptureCandidate page({DateTime? at, int? amount = 1250}) =>
      c(at: at, amount: amount, source: CaptureSource.accessibility);

  test('同页同金额的多次抓帧合并为一条', () {
    final result = mergeCandidates([
      page(at: base),
      page(at: base.add(const Duration(seconds: 3))),
      page(at: base.add(const Duration(seconds: 6))),
    ]);
    expect(result, hasLength(1));
  });

  test('页面候选并进同一笔的通知', () {
    final result = mergeCandidates([
      c(at: base),
      page(at: base.add(const Duration(seconds: 2))),
    ]);
    expect(result, hasLength(1));
  });

  test('两条同额通知各自成笔，页面候选不额外成笔', () {
    final result = mergeCandidates([
      c(at: base),
      c(at: base.add(const Duration(seconds: 30))),
      page(at: base.add(const Duration(seconds: 2))),
    ]);
    expect(result, hasLength(2));
  });

  test('通知与页面相隔超过窗口时各记一笔', () {
    final result = mergeCandidates([
      c(at: base),
      page(at: base.add(const Duration(seconds: 180))),
    ]);
    expect(result, hasLength(2));
  });

  test('窗口内已入账的记忆会吞掉后续抓帧', () {
    final result = mergeCandidates(
      [page(at: base.add(const Duration(seconds: 30)))],
      recent: [page(at: base)],
    );
    expect(result, isEmpty);
  });

  test('超出窗口的旧记忆不再参与合并', () {
    final result = mergeCandidates(
      [page(at: base.add(const Duration(seconds: 200)))],
      recent: [page(at: base)],
    );
    expect(result, hasLength(1));
  });

  test('不同金额或不同包不合并', () {
    final result = mergeCandidates([
      page(at: base),
      page(amount: 880, at: base),
      c(pkg: 'com.eg.android.AlipayGphone', at: base),
    ]);
    expect(result, hasLength(3));
  });

  test('无金额的候选原样保留、不参与合并', () {
    final result = mergeCandidates([
      page(amount: null, at: base),
      page(amount: null, at: base),
    ]);
    expect(result, hasLength(2));
  });

  test('无时间的候选原样保留、不参与合并', () {
    final result = mergeCandidates([
      page(at: base),
      page(at: null),
    ]);
    expect(result, hasLength(2));
  });
}
