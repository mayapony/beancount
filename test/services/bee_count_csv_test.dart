import 'dart:convert';
import 'dart:io';

import 'package:bean_count/data/db/enums.dart';
import 'package:bean_count/services/import/bee_count_csv.dart';
import 'package:flutter_test/flutter_test.dart';

List<int> _fixture(String name) =>
    File('test/fixtures/$name').readAsBytesSync();

void main() {
  group('解析 BeeCount CSV', () {
    test('中文表头：BOM、时间两侧空格、标签、附件都能认', () {
      final result = parseBeeCountCsv(_fixture('beecount_sample.csv'));

      expect(result.ok, isTrue, reason: result.fatal);
      // 样本 10 行，其中 1 行转账被跳过
      expect(result.totalRows, 10);
      expect(result.rows, hasLength(9));
      expect(result.skipped, hasLength(1));
      expect(result.skipped.single.reason, '转账暂不支持');

      final first = result.rows.first;
      expect(first.lineNumber, 2);
      expect(first.type, EntryType.expense);
      expect(first.categoryName, '餐饮');
      expect(first.amountCents, 3002);
      expect(first.happenedAt, DateTime(2026, 10, 17, 19, 27));
      expect(first.tags, ['图片记账', 'AI记账']);
      expect(first.attachments, ['sha_aaaa1111.jpg']);
      expect(first.note, '街角炸鸡');
      expect(first.currency, 'CNY');
    });

    test('英文表头同样可解析', () {
      final result = parseBeeCountCsv(_fixture('beecount_sample_en.csv'));

      expect(result.ok, isTrue, reason: result.fatal);
      expect(result.rows, hasLength(2));
      expect(result.rows.first.type, EntryType.expense);
      expect(result.rows.first.categoryName, 'Food');
      expect(result.rows[1].type, EntryType.income);
      expect(result.skipped.single.reason, '转账暂不支持');
    });

    test('缺必需列直接拒绝，并说清缺哪个', () {
      const csv = '类型,分类,备注\n支出,餐饮,测试\n';
      final result = parseBeeCountCsv(utf8.encode(csv));

      expect(result.ok, isFalse);
      expect(result.fatal, contains('金额'));
      expect(result.fatal, contains('时间'));
    });

    test('单行金额/时间不合法只跳过该行', () {
      const csv = '类型,分类,金额,时间\n'
          '支出,餐饮,12.34,  2026-10-17 12:30:00  \n'
          '支出,餐饮,abc,  2026-10-17 12:31:00  \n'
          '支出,餐饮,10.00,不是时间\n';
      final result = parseBeeCountCsv(utf8.encode(csv));

      expect(result.rows, hasLength(1));
      expect(result.skipped, hasLength(2));
      expect(result.skipped.first.reason, contains('金额无法解析'));
      expect(result.skipped.last.reason, contains('时间无法解析'));
      expect(result.skipped.first.lineNumber, 3);
      expect(result.skipped.last.lineNumber, 4);
    });
  });

  group('金额与时间', () {
    test('金额按分解析，不用浮点', () {
      expect(parseAmountToCents('38.5'), 3850);
      expect(parseAmountToCents('0.10'), 10);
      expect(parseAmountToCents('0.20'), 20);
      expect(parseAmountToCents('14519.01'), 1451901);
      expect(parseAmountToCents('300'), 30000);
      expect(parseAmountToCents('1,234.50'), null, reason: '逗号由调用方先清');
      expect(parseAmountToCents('abc'), isNull);
      expect(parseAmountToCents('-5.00'), -500);
    });

    test('时间允许两位秒、斜杠与省略秒', () {
      expect(
        parseBeeCountTime('  2026-10-17 12:30:00  '),
        DateTime(2026, 10, 17, 12, 30),
      );
      expect(
        parseBeeCountTime('2026/10/17 12:30'),
        DateTime(2026, 10, 17, 12, 30),
      );
      expect(parseBeeCountTime('  '), isNull);
      expect(parseBeeCountTime('2026-13-40 99:99:00'), isNull);
    });
  });
}
