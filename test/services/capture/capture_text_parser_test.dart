import 'package:bean_count/services/capture/capture_text_parser.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('parseCaptureAmount', () {
    test('¥ 前缀', () => expect(parseCaptureAmount('¥12.50'), 1250));

    test('￥ 前缀带空格', () => expect(parseCaptureAmount('￥ 38.50'), 3850));

    test('元 后缀', () => expect(parseCaptureAmount('38.50元'), 3850));

    test('千分位', () => expect(parseCaptureAmount('1,234.50'), 123450));

    test('整数 + 元', () => expect(parseCaptureAmount('支付 12 元'), 1200));

    test('合计行优先', () {
      expect(parseCaptureAmount('¥38.50\n¥6.00\n合计 ¥44.50'), 4450);
    });

    test('实付优先于更大的原价', () {
      expect(parseCaptureAmount('原价 ¥200\n实付 ¥180'), 18000);
    });

    test('无合计行取最大金额', () {
      expect(parseCaptureAmount('¥38.50\n¥6.00'), 3850);
    });

    test('无金额返回 null', () {
      expect(parseCaptureAmount('订单号 202610251234'), isNull);
    });

    test('空文本返回 null', () {
      expect(parseCaptureAmount(''), isNull);
    });
  });
}
