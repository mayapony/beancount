import 'package:bean_count/data/category_library.dart';
import 'package:bean_count/data/db/enums.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('分类库', () {
    test('按名字搜索', () {
      final hits = searchCategoryLibrary('打车');
      expect(hits.map((e) => e.category.name), contains('打车'));
      expect(hits.first.parent?.name, '出行交通');
    });

    test('按别名搜索', () {
      expect(
        searchCategoryLibrary('滴滴').map((e) => e.category.name),
        contains('打车'),
      );
      expect(
        searchCategoryLibrary('外卖').map((e) => e.category.name),
        contains('外卖'),
      );
    });

    test('父级命中时把它的二级一起列出来', () {
      final hits = searchCategoryLibrary('交通');
      final names = hits.map((e) => e.category.name).toSet();
      expect(names, contains('出行交通'));
      expect(names, contains('打车'));
      expect(names, contains('停车费'));
    });

    test('搜索不区分大小写', () {
      expect(
        searchCategoryLibrary('FOOD').map((e) => e.category.name),
        contains('食品餐饮'),
      );
    });

    test('空搜索返回全部，且每条都有合法图标 key', () {
      final all = flattenCategoryLibrary();
      expect(all.length, greaterThan(50));
      for (final entry in all) {
        expect(entry.category.iconKey, isNotEmpty);
        expect(entry.displayPath, contains(entry.category.name));
      }
    });

    test('按收支类型过滤', () {
      final income = flattenCategoryLibrary(type: CategoryType.income);
      expect(income.map((e) => e.category.name), contains('工资'));
      expect(income.map((e) => e.category.name), isNot(contains('打车')));

      final expense = flattenCategoryLibrary(type: CategoryType.expense);
      expect(expense.map((e) => e.category.name), contains('打车'));
    });

    test('二级分类都有父级，一级没有', () {
      for (final entry in flattenCategoryLibrary()) {
        if (entry.category.name == '打车') {
          expect(entry.parent, isNotNull);
        }
        if (entry.category.name == '出行交通') {
          expect(entry.parent, isNull);
        }
      }
    });
  });
  group('文本反向匹配', () {
    test('文本里出现商户名能命中分类', () {
      final hits = libraryEntriesInText('微信支付 滴滴出行 支付 ¥12.00');
      expect(hits.map((e) => e.displayPath), contains('出行交通 / 打车'));
    });

    test('长词优先', () {
      final hits = libraryEntriesInText('叮咚买菜');
      expect(hits.first.displayPath, contains('买菜'));
    });

    test('空文本与无命中返回空', () {
      expect(libraryEntriesInText(''), isEmpty);
      expect(libraryEntriesInText('支付宝 支付成功 ¥5'), isEmpty);
    });

    test('按类型过滤', () {
      final income = libraryEntriesInText('工资到账', type: CategoryType.income);
      expect(income.map((e) => e.category.name), contains('工资'));
    });
  });
}