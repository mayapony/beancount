import 'package:bean_count/data/db/app_database.dart';
import 'package:bean_count/data/db/enums.dart';
import 'package:bean_count/services/ocr/entry_matching.dart';
import 'package:flutter_test/flutter_test.dart';

Category _cat(String name, CategoryType type, {String? id}) => Category(
      id: id ?? 'cat-$name',
      name: name,
      type: type,
      color: 0,
      icon: '',
      sortOrder: 0,
      createdAt: DateTime(2026, 10, 18),
    );

Account _account(String name, {String? id}) => Account(
      id: id ?? 'acc-$name',
      name: name,
      type: AccountType.wallet,
      initialBalanceCents: 0,
      sortOrder: 0,
      currency: 'CNY',
      createdAt: DateTime(2026, 10, 18),
    );

void main() {
  group('normalizeName', () {
    test('去空白与标点', () {
      expect(normalizeName(' 交 通 '), '交通');
      expect(normalizeName('咖啡（店）'), '咖啡店');
      expect(normalizeName('微信支付·零钱'), '微信支付零钱');
    });

    test('全角转半角、大小写归一', () {
      expect(normalizeName('ＡＢＣ'), 'abc');
      expect(normalizeName('Starbucks'), 'starbucks');
      expect(normalizeName('１２３'), '123');
    });

    test('空值返回空串', () {
      expect(normalizeName(null), '');
      expect(normalizeName('  '), '');
    });
  });

  group('matchCategory', () {
    final categories = [
      _cat('餐饮', CategoryType.expense),
      _cat('交通', CategoryType.expense),
      _cat('工资', CategoryType.income),
    ];

    test('同名直接命中', () {
      final match = matchCategory('餐饮', categories, CategoryType.expense);
      expect(match?.name, '餐饮');
    });

    test('别名命中用户改名后的分类', () {
      final renamed = [_cat('吃饭', CategoryType.expense)];
      final match = matchCategory('餐饮', renamed, CategoryType.expense);
      expect(match?.name, '吃饭');
    });

    test('归一化后命中', () {
      final match = matchCategory(' 交 通 ', categories, CategoryType.expense);
      expect(match?.name, '交通');
    });

    test('类型不同不命中', () {
      expect(matchCategory('工资', categories, CategoryType.expense), isNull);
    });

    test('认不出返回 null，不瞎猜', () {
      expect(matchCategory('维修', categories, CategoryType.expense), isNull);
      expect(matchCategory(null, categories, CategoryType.expense), isNull);
    });
  });

  group('tagCandidates', () {
    test('已有标签优先复用', () {
      final tags = tagCandidates(
        '微信支付 ¥38.50 咖啡',
        existingNames: ['微信支付'],
      );
      expect(tags.first, '微信支付');
      expect(tags, contains('咖啡'));
      expect(tags.length, lessThanOrEqualTo(2));
    });

    test('最多两个候选', () {
      final tags = tagCandidates('微信支付 咖啡 打车 超市');
      expect(tags.length, 2);
    });

    test('同名不重复', () {
      final tags = tagCandidates('咖啡 拿铁 美式');
      expect(tags, ['咖啡']);
    });

    test('没有命中或没有文本返回空', () {
      expect(tagCandidates('¥12.00'), isEmpty);
      expect(tagCandidates(''), isEmpty);
      expect(tagCandidates(null), isEmpty);
    });
  });

  group('matchAccount', () {
    final accounts = [
      _account('默认账户'),
      _account('微信零钱'),
      _account('招商银行'),
    ];

    test('账户名包含在文本里', () {
      final match = matchAccount('招商银行信用卡 ¥38.50', accounts);
      expect(match?.name, '招商银行');
    });

    test('别名组命中', () {
      final match = matchAccount('微信支付 ¥38.50', accounts);
      expect(match?.name, '微信零钱');
    });

    test('命中多个时取名称最长的', () {
      final withBoth = [
        _account('微信'),
        _account('微信零钱'),
      ];
      final match = matchAccount('微信支付', withBoth);
      expect(match?.name, '微信零钱');
    });

    test('不做模糊匹配，认不出返回 null', () {
      expect(matchAccount('招行信用卡 ¥38.50', accounts), isNull);
      expect(matchAccount('', accounts), isNull);
      expect(matchAccount('微信支付', const []), isNull);
    });
  });
}
