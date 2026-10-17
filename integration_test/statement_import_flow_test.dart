import 'dart:convert';

import 'package:bean_count/data/db/app_database.dart';
import 'package:bean_count/data/db/connection.dart';
import 'package:bean_count/data/repositories/account_repository.dart';
import 'package:bean_count/data/repositories/attachment_repository.dart';
import 'package:bean_count/data/repositories/category_repository.dart';
import 'package:bean_count/data/repositories/transaction_repository.dart';
import 'package:bean_count/services/import/import_service.dart';
import 'package:bean_count/services/import/statement_import.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'dart:io';

/// 真机/模拟器：设备上的临时目录 + 真实 sqlite，走一遍支付宝账单导入。
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  const statement = '''
支付宝交易记录明细查询
---------------------------------交易记录明细列表------------------------------------
交易时间,交易分类,交易对方,商品说明,收/支,金额,收/付款方式,交易状态,交易订单号,商家订单号,备注
2026-10-17 19:27:00,餐饮美食,街角炸鸡,炸鸡套餐,支出,38.50,余额宝,交易成功,2026101722001,SH001,
2026-10-15 09:00:00,转账红包,张三,收到红包,收入,120.00,余额,交易成功,2026101522002,NULL,
''';

  testWidgets('支付宝账单：解析 → 计划 → 落库', (tester) async {
    final base = await getApplicationDocumentsDirectory();
    final dir = Directory(p.join(base.path, 'it_statement_flow'));
    if (await dir.exists()) await dir.delete(recursive: true);

    final db = AppDatabase(openInMemoryConnection());
    final categories = CategoryRepository(db);
    final transactions = TransactionRepository(db);
    final attachments = AttachmentRepository(db, directory: dir);
    final importer = ImportService(
      db: db,
      categories: categories,
      accounts: AccountRepository(db),
      transactions: transactions,
      attachments: attachments,
    );
    await db.select(db.categories).get();
    await attachments.ensureReady();

    final parsed = await parseImportFile(utf8.encode(statement));
    expect(parsed.kind, StatementKind.alipay);

    final plan = await planImport(
      service: importer,
      parsed: parsed.result,
      attachmentSizes: const {},
    );
    await importer.apply(plan, attachments: const {});

    expect(await transactions.count(), 2);
    final rows = await transactions.exportRows();
    expect(
      rows.where((r) => r.accountName == '支付宝').length,
      2,
      reason: '两笔都归到平台账户',
    );
    expect(
      rows.map((r) => r.transaction.amountCents).toSet(),
      {3850, 12000},
    );

    await db.close();
    if (await dir.exists()) await dir.delete(recursive: true);
  });
}
