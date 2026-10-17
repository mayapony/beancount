import 'dart:convert';

import 'package:bean_count/data/db/enums.dart';
import 'package:bean_count/services/import/statement_import.dart';
import 'package:excel/excel.dart';
import 'package:flutter_test/flutter_test.dart';
import 'dart:io';

const _alipay = '''
支付宝交易记录明细查询
账号:138****0000
起始日期:[2026-10-01 00:00:00]    终止日期:[2026-10-31 23:59:59]
---------------------------------交易记录明细列表------------------------------------
交易时间,交易分类,交易对方,商品说明,收/支,金额,收/付款方式,交易状态,交易订单号,商家订单号,备注
2026-10-17 19:27:00,餐饮美食,街角炸鸡,炸鸡套餐,支出,38.50,余额宝,交易成功,2026101722001,SH001,
2026-10-15 09:00:00,转账红包,张三,收到红包,收入,120.00,余额,交易成功,2026101522002,NULL,
2026-10-14 08:00:00,投资理财,余额宝,余额宝收益,不计收支,0.12,余额宝,交易成功,2026101422003,NULL,
2026-10-13 20:00:00,日用百货,超市,纸巾,支出,25.00,招商银行储蓄卡(1234),交易关闭,2026101322004,NULL,
''';

const _wechat = '''
微信支付账单明细
微信昵称:[小金豆]
起始时间:[2026-10-01 00:00:00] 终止时间:[2026-10-31 23:59:59]
----------------------微信支付账单明细列表--------------------
交易时间,交易类型,交易对方,商品,收/支,金额(元),支付方式,当前状态,交易单号,商户单号,备注
2026-10-16 12:10:00,商户消费,美团,午餐,支出,¥32.00,零钱,支付成功,4200001,M001,
2026-10-12 08:30:00,转账,李四,转账,/,¥200.00,零钱,已转账,4200002,M002,
2026-10-11 19:00:00,商户消费,滴滴,打车,支出,¥18.50,零钱,已全额退款,4200003,M003,
''';

void main() {
  group('格式识别', () {
    test('支付宝账单被认出', () async {
      final parsed = await parseImportFile(utf8.encode(_alipay));
      expect(parsed.kind, StatementKind.alipay);
      expect(parsed.result.ok, isTrue);
    });

    test('微信账单被认出', () async {
      final parsed = await parseImportFile(utf8.encode(_wechat));
      expect(parsed.kind, StatementKind.wechat);
      expect(parsed.result.ok, isTrue);
    });

    test('未知格式给出可读提示', () async {
      final parsed = await parseImportFile(
        utf8.encode('姓名,年龄\n张三,20\n'),
      );
      expect(parsed.kind, StatementKind.unknown);
      expect(parsed.result.ok, isFalse);
      expect(parsed.result.fatal, contains('认不出'));
      expect(parsed.result.rows, isEmpty);
    });
  });

  group('支付宝账单', () {
    test('支出/收入解析正确，不计收支与关闭行跳过', () async {
      final parsed = await parseImportFile(utf8.encode(_alipay));
      final rows = parsed.result.rows;

      expect(rows, hasLength(2));
      expect(rows.first.type, EntryType.expense);
      expect(rows.first.amountCents, 3850);
      expect(rows.first.categoryName, '餐饮');
      expect(rows.first.note, '炸鸡套餐');
      expect(rows.first.accountName, '支付宝');
      expect(rows.first.happenedAt, DateTime(2026, 10, 17, 19, 27));

      expect(rows.last.type, EntryType.income);
      expect(rows.last.amountCents, 12000);
      expect(rows.last.categoryName, '红包');

      final reasons = parsed.result.skipped.map((s) => s.reason).join('|');
      expect(reasons, contains('不计收支'));
      expect(reasons, contains('未完成'));
      expect(parsed.result.skipped.map((s) => s.lineNumber), contains(9));
    });

    test('GBK 编码也能正确读出中文', () async {
      // 真实支付宝导出就是 GBK：用二进制样本，避免测试里再造一遍编码
      final bytes = File('test/fixtures/alipay_sample_gbk.csv').readAsBytesSync();
      final parsed = await parseImportFile(bytes);
      expect(parsed.kind, StatementKind.alipay);
      expect(parsed.result.rows.first.categoryName, '餐饮');
      expect(parsed.result.rows.first.note, '炸鸡套餐');
    });
  });

  group('微信账单', () {
    test('去掉 ¥、跳过 / 与退款行', () async {
      final parsed = await parseImportFile(utf8.encode(_wechat));
      final rows = parsed.result.rows;

      expect(rows, hasLength(1));
      expect(rows.single.amountCents, 3200, reason: '¥32.00 → 3200 分');
      expect(rows.single.accountName, '微信支付');
      expect(rows.single.note, '午餐');
      expect(rows.single.categoryName, '其他');

      expect(parsed.result.skipped, hasLength(2));
      expect(
        parsed.result.skipped.map((s) => s.reason).join('|'),
        contains('未完成'),
      );
      expect(
        parsed.result.skipped.map((s) => s.reason).join('|'),
        contains('不计收支'),
      );
    });
  });

  group('分类映射', () {
    test('常见对方分类映射到本地分类', () {
      expect(
        mapStatementCategory(rawCategory: '餐饮美食', isIncome: false),
        '餐饮',
      );
      expect(mapStatementCategory(rawCategory: '交通出行', isIncome: false), '交通');
      expect(mapStatementCategory(rawCategory: '服饰装扮', isIncome: false), '购物');
      expect(mapStatementCategory(rawCategory: '医疗健康', isIncome: false), '医疗');
      expect(mapStatementCategory(rawCategory: '酒店旅游', isIncome: false), '旅行');
      expect(mapStatementCategory(rawCategory: '工资', isIncome: true), '工资');
      expect(mapStatementCategory(rawCategory: '理财收益', isIncome: true), '理财');
    });

    test('映射不到时兜底，不抛错', () {
      expect(mapStatementCategory(rawCategory: '玄学', isIncome: false), '其他');
      expect(mapStatementCategory(rawCategory: '玄学', isIncome: true), '其他收入');
    });
  });

  group('Excel', () {
    test('BeeCount 表头的 xlsx 能解析', () async {
      final excel = Excel.createExcel();
      final sheet = excel['Sheet1'];
      const header = ['类型', '分类', '二级分类', '金额', '币种', '账户', '备注', '时间'];
      for (var c = 0; c < header.length; c++) {
        sheet.cell(
          CellIndex.indexByColumnRow(columnIndex: c, rowIndex: 0),
        ).value = TextCellValue(header[c]);
      }
      final rows = [
        ['支出', '餐饮', '', '38.50', 'CNY', '现金', '牛肉面', '2026-10-17 12:00:00'],
        ['收入', '工资', '', '12000.00', 'CNY', '银行卡', '月薪', '2026-10-15 09:00:00'],
      ];
      for (var r = 0; r < rows.length; r++) {
        for (var c = 0; c < rows[r].length; c++) {
          sheet.cell(
            CellIndex.indexByColumnRow(columnIndex: c, rowIndex: r + 1),
          ).value = TextCellValue(rows[r][c]);
        }
      }
      final bytes = excel.encode()!;

      final parsed = await parseImportFile(bytes, fileName: '账单.xlsx');
      expect(parsed.kind, StatementKind.beecount);
      expect(parsed.result.ok, isTrue);
      expect(parsed.result.rows, hasLength(2));
      expect(parsed.result.rows.first.amountCents, 3850);
      expect(parsed.result.rows.last.categoryName, '工资');
    });

    test('支付宝表头的 xlsx 也能解析', () async {
      final excel = Excel.createExcel();
      final sheet = excel['Sheet1'];
      final lines = _alipay.trim().split('\n');
      for (var r = 0; r < lines.length; r++) {
        final cells = lines[r].split(',');
        for (var c = 0; c < cells.length; c++) {
          sheet.cell(
            CellIndex.indexByColumnRow(columnIndex: c, rowIndex: r),
          ).value = TextCellValue(cells[c]);
        }
      }

      final parsed = await parseImportFile(excel.encode()!);
      expect(parsed.kind, StatementKind.alipay);
      expect(parsed.result.rows, hasLength(2));
    });
  });
}
