import 'dart:convert';
import 'dart:io';

import 'package:bean_count/data/db/app_database.dart';
import 'package:bean_count/data/db/connection.dart';
import 'package:bean_count/data/repositories/account_repository.dart';
import 'package:bean_count/data/repositories/attachment_repository.dart';
import 'package:bean_count/data/repositories/category_repository.dart';
import 'package:bean_count/data/repositories/transaction_repository.dart';
import 'package:bean_count/services/import/import_service.dart';
import 'package:bean_count/services/import/statement_import.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gbk_codec/gbk_codec.dart';

/// 真实路径：GBK 编码的支付宝账单 → 解析 → 建计划 → 落库。
void main() {
  const statement = '''
支付宝交易记录明细查询
账号:138****0000
---------------------------------交易记录明细列表------------------------------------
交易时间,交易分类,交易对方,商品说明,收/支,金额,收/付款方式,交易状态,交易订单号,商家订单号,备注
2026-10-17 19:27:00,餐饮美食,街角炸鸡,炸鸡套餐,支出,38.50,余额宝,交易成功,2026101722001,SH001,
2026-10-15 09:00:00,转账红包,张三,收到红包,收入,120.00,余额,交易成功,2026101522002,NULL,
2026-10-14 08:00:00,投资理财,余额宝,余额宝收益,不计收支,0.12,余额宝,交易成功,2026101422003,NULL,
''';

  late AppDatabase db;
  late Directory tmp;
  late ImportService importer;
  late TransactionRepository transactions;
  late CategoryRepository categories;
  late AttachmentRepository attachments;

  setUp(() async {
    db = AppDatabase(openInMemoryConnection());
    tmp = await Directory.systemTemp.createTemp('bean_statement');
    categories = CategoryRepository(db);
    transactions = TransactionRepository(db);
    attachments = AttachmentRepository(db, directory: tmp);
    importer = ImportService(
      db: db,
      categories: categories,
      accounts: AccountRepository(db),
      transactions: transactions,
      attachments: attachments,
    );
    await db.select(db.categories).get();
  });

  tearDown(() async {
    await db.close();
    if (await tmp.exists()) await tmp.delete(recursive: true);
  });

  test('GBK 支付宝账单：预览数字正确，落库后分类与账户正确', () async {
    final parsed = await parseImportFile(gbk.encode(statement));
    expect(parsed.kind, StatementKind.alipay);
    expect(parsed.result.rows, hasLength(2));
    expect(parsed.result.skipped, hasLength(1));

    final plan = await planImport(
      service: importer,
      parsed: parsed.result,
      attachmentSizes: const {},
    );
    expect(plan.entries, hasLength(2));

    await importer.apply(plan, attachments: const {});
    expect(await transactions.count(), 2);

    final rows = await transactions.exportRows();
    final expense = rows.firstWhere((r) => r.transaction.type.name == 'expense');
    expect(expense.categoryPath, contains('餐饮'));
    expect(expense.accountName, '支付宝', reason: '平台账单统一归到平台账户');
    expect(expense.transaction.amountCents, 3850);

    final income = rows.firstWhere((r) => r.transaction.type.name == 'income');
    expect(income.categoryPath, contains('红包'));
    expect(income.transaction.amountCents, 12000);

    // 再导一次不新增（去重生效）
    final again = await planImport(
      service: importer,
      parsed: (await parseImportFile(gbk.encode(statement))).result,
      attachmentSizes: const {},
    );
    await importer.apply(again, attachments: const {});
    expect(await transactions.count(), 2);
  });

  test('UTF-8 的微信账单也能直接导入', () async {
    const wechat = '''
微信支付账单明细
----------------------微信支付账单明细列表--------------------
交易时间,交易类型,交易对方,商品,收/支,金额(元),支付方式,当前状态,交易单号,商户单号
2026-10-16 12:10:00,商户消费,美团,午餐,支出,¥32.00,零钱,支付成功,4200001,M001
''';
    final parsed = await parseImportFile(utf8.encode(wechat));
    expect(parsed.kind, StatementKind.wechat);

    final plan = await planImport(
      service: importer,
      parsed: parsed.result,
      attachmentSizes: const {},
    );
    await importer.apply(plan, attachments: const {});

    final row = (await transactions.exportRows()).single;
    expect(row.accountName, '微信支付');
    expect(row.transaction.amountCents, 3200);
  });
}
