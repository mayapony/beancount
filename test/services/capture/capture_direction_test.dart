import 'package:bean_count/services/capture/capture_candidate.dart';
import 'package:bean_count/services/capture/capture_text_parser.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('parseCaptureDirection', () {
    test('付款默认 expense', () {
      expect(
        parseCaptureDirection('微信支付 ¥12.50'),
        CaptureDirection.expense,
      );
    });

    test('收款 income', () {
      expect(
        parseCaptureDirection('收款 ¥100 已到账'),
        CaptureDirection.income,
      );
    });

    test('退款 refund', () {
      expect(
        parseCaptureDirection('退款 ¥50 已原路退回'),
        CaptureDirection.refund,
      );
    });

    test('退款优先于收款', () {
      expect(
        parseCaptureDirection('收款退款 ¥50'),
        CaptureDirection.refund,
      );
    });
  });

  group('isCaptureExcluded', () {
    test('余额排除', () {
      expect(isCaptureExcluded('余额 ¥1204.00'), isTrue);
    });

    test('优惠排除', () {
      expect(isCaptureExcluded('已优惠 ¥5.00'), isTrue);
    });

    test('立减排除', () {
      expect(isCaptureExcluded('立减 ¥2.00'), isTrue);
    });

    test('带支付词的立减不排除', () {
      expect(isCaptureExcluded('支付 ¥12.50 立减 ¥2'), isFalse);
    });

    test('普通支付不排除', () {
      expect(isCaptureExcluded('微信支付 ¥12.50'), isFalse);
    });
  });
}
