import 'package:bean_count/utils/fx.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('换算', () {
    test('USD 100 @ 7.25 → 725 元', () {
      expect(
        baseCentsOf(originalCents: 10000, ratePpm: 7250000),
        72500,
      );
    });

    test('四舍五入到分', () {
      // 1 分 × 7.255 = 7.255 分 → 7 分
      expect(baseCentsOf(originalCents: 1, ratePpm: 7255000), 7);
      // 1 分 × 7.5 = 7.5 分 → 8 分
      expect(baseCentsOf(originalCents: 1, ratePpm: 7500000), 8);
      // 1 分 × 7.4 = 7.4 分 → 7 分
      expect(baseCentsOf(originalCents: 1, ratePpm: 7400000), 7);
    });

    test('汇率必须为正', () {
      expect(
        () => baseCentsOf(originalCents: 100, ratePpm: 0),
        throwsA(isA<ArgumentError>()),
      );
      expect(() => ppmOf(0), throwsA(isA<ArgumentError>()));
    });

    test('ppm 与文本互转', () {
      expect(ppmOf(7.25), 7250000);
      expect(ppmOf(1), 1000000);
      expect(rateTextOf(7250000), '7.25');
      expect(rateTextOf(1000000), '1');
      expect(rateTextOf(1110000), '1.11');
    });

    test('解析用户输入', () {
      expect(parseRateText('7.25'), 7250000);
      expect(parseRateText('0'), isNull);
      expect(parseRateText('-1'), isNull);
      expect(parseRateText('abc'), isNull);
      expect(parseRateText('1,234.5'), 1234500000);
      expect(parseRateText('99999999'), isNull, reason: '超过上限');
    });
  });

  group('显示', () {
    test('币种符号', () {
      expect(currencySymbolOf('USD'), r'US$');
      expect(currencySymbolOf('CNY'), '¥');
      expect(currencySymbolOf('EUR'), '€');
      expect(currencySymbolOf('XYZ'), 'XYZ ');
    });

    test('带符号金额文本与千分位', () {
      expect(formatForeign(10000, 'USD'), r'US$100.00');
      expect(formatForeign(1234567, 'USD'), r'US$12,345.67');
      expect(formatForeign(-500, 'EUR'), '-€5.00');
    });

    test('本位币判断', () {
      expect(isBaseCurrency('CNY'), isTrue);
      expect(isBaseCurrency('usd'), isFalse);
    });
  });
}
