import 'package:bean_count/services/ocr/receipt_parser.dart';
import 'package:flutter_test/flutter_test.dart';

/// 真实视觉模型输出（含噪声）：用它当基准，比手写"完美文本"更能反映实际。
const _visionOutput = '''
金豆餐厅消费小票
牛内面 ¥38.50
可乐
合計
¥6.00
感谢光临
¥44.50
2026-10-18 12:30
''';

void main() {
  group('金额', () {
    test('合计行优先，不被小计带偏', () {
      final guess = parseReceiptText(_visionOutput);
      expect(guess.amountCents, 4450, reason: '取 44.50，而不是 38.50');
      expect(guess.confidence, ReceiptConfidence.amount);
    });

    test('没有合计行时取最大金额', () {
      final guess = parseReceiptText('牛肉面 ¥38.50\n可乐 ¥6.00');
      expect(guess.amountCents, 3850);
    });

    test('支持 ￥、元、千分位', () {
      expect(parseReceiptText('合计 ￥1,234.50').amountCents, 123450);
      expect(parseReceiptText('实付 38.5元').amountCents, 3850);
      expect(parseReceiptText('总计 ¥1234.50').amountCents, 123450);
    });

    test('过滤年份与订单号', () {
      final guess = parseReceiptText('2026-10-18\n订单号 20261018000123\n合计 ¥12.00');
      expect(guess.amountCents, 1200);
    });
  });

  group('分类', () {
    test('餐厅 → 餐饮', () {
      expect(parseReceiptText(_visionOutput).categoryName, '餐饮');
    });

    test('打车 → 交通', () {
      expect(parseReceiptText('滴滴出行 ¥25.00').categoryName, '交通');
    });

    test('超市 → 购物', () {
      expect(parseReceiptText('便利超市 ¥62.10').categoryName, '购物');
    });

    test('猜不出时不猜', () {
      expect(parseReceiptText('¥12.00').categoryName, isNull);
    });
  });

  group('日期与备注', () {
    test('识别 YYYY-MM-DD', () {
      final guess = parseReceiptText(_visionOutput, now: DateTime(2026, 10, 20, 9));
      expect(guess.happenedAt, DateTime(2026, 10, 18, 9));
    });

    test('识别 年月日', () {
      final guess = parseReceiptText(
        '合计 ¥20.00\n2026年3月5日',
        now: DateTime(2026, 10, 20),
      );
      expect(guess.happenedAt?.month, 3);
      expect(guess.happenedAt?.day, 5);
    });

    test('只有月-日时补当年', () {
      final guess = parseReceiptText('合计 ¥20.00\n3-5', now: DateTime(2026, 10, 20));
      expect(guess.happenedAt, DateTime(2026, 3, 5, 0, 0));
    });

    test('备注取店名并去掉"消费小票"', () {
      final guess = parseReceiptText(_visionOutput);
      expect(guess.note, contains('金豆餐厅'));
      expect(guess.note, isNot(contains('消费小票')));
    });
  });

  group('标签与账户线索', () {
    test('从支付渠道与消费词里取标签，最多两个', () {
      final guess = parseReceiptText('微信支付 ¥38.50\n星巴克咖啡');
      expect(guess.tagNames, containsAll(<String>['微信支付', '咖啡']));
      expect(guess.tagNames.length, lessThanOrEqualTo(2));
    });

    test('认不出支付渠道时账户线索为空', () {
      final guess = parseReceiptText('牛肉面 ¥38.50');
      expect(guess.accountName, isNull);
    });

    test('账户线索归一化为规范名', () {
      expect(parseReceiptText('支付宝 ¥12.00').accountName, '支付宝');
      expect(parseReceiptText('招行信用卡 尾号1234').accountName, '银行卡');
    });

    test('标签不改变置信度判定', () {
      final guess = parseReceiptText('微信支付');
      expect(guess.tagNames, isNotEmpty);
      expect(
        guess.confidence,
        ReceiptConfidence.categoryOnly,
        reason: '置信度仍只看金额/分类/备注，标签不参与',
      );
    });
  });

  group('边界', () {
    test('空文本', () {
      final guess = parseReceiptText('   ');
      expect(guess.isEmpty, isTrue);
      expect(guess.confidence, ReceiptConfidence.none);
    });

    test('只有数字', () {
      final guess = parseReceiptText('1234567890123');
      expect(guess.hasAmount, isFalse, reason: '长串数字不当金额');
    });

    test('只有分类没有金额时置信度降级', () {
      final guess = parseReceiptText('星巴克咖啡');
      expect(guess.categoryName, '餐饮');
      expect(guess.confidence, ReceiptConfidence.categoryOnly);
    });
  });
}
