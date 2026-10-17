import 'dart:convert';
import 'dart:typed_data';

import 'package:bean_count/data/db/app_database.dart';
import 'package:bean_count/data/db/enums.dart';
import 'package:bean_count/data/repositories/attachment_repository.dart';
import 'package:bean_count/data/repositories/account_repository.dart';
import 'package:bean_count/data/repositories/category_repository.dart';
import 'package:bean_count/data/repositories/transaction_repository.dart';

/// 48×48 的暖金 PNG：截图里的"记账凭证"占位，让它看起来像真图。
final Uint8List _demoImage = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAADAAAAAwCAIAAADYYG7QAAAAO0lEQVR42u3OoQ0AAAgDsHn+t3yJ5wuCaNID'
  'mul6JUJCQkJCQkJCQkJCQkJCQkJCQkJCQkJCQkJCd6EFPiKO02DImnIAAAAASUVORK5CYII=',
);

/// 清空交易后重新造演示数据（截图脚本之间互不污染）。
Future<void> resetDemoLedger(
  AppDatabase db, {
  AttachmentRepository? attachments,
}) async {
  await db.transaction(() async {
    await db.delete(db.transactionTags).go();
    await db.delete(db.attachments).go();
    await db.delete(db.transactions).go();
    await db.delete(db.tags).go();
  });
  if (attachments != null) {
    await attachments.sweepOrphans();
  }
  await seedDemoLedger(db, attachments: attachments);
}

/// 给截图脚本用的演示账本：只写进内存库，不参与任何断言。
///
/// 明细页接库之后，截图里如果只有空状态就看不出排版，所以这里按
/// 原来的 demo 数据节奏（今天 / 昨天 / 前天）造几笔；前两笔带一张图，
/// 用来验证缩略图的排版。
Future<void> seedDemoLedger(
  AppDatabase db, {
  AttachmentRepository? attachments,
}) async {
  final repo = TransactionRepository(db);
  if (await repo.count() > 0) return;

  final categories = CategoryRepository(db);
  Future<String> cat(String name, CategoryType type) async {
    final found = await categories.findByName(name, type);
    if (found == null) throw StateError('缺少种子分类：$name');
    return found.id;
  }

  // 账户：让资产页和明细行都有真实内容
  final accounts = AccountRepository(db);
  final alipay = await accounts.ensure(name: '支付宝');
  final wechat = await accounts.ensure(name: '微信');
  final cmb = await accounts.ensure(name: '招商银行', type: AccountType.debit);
  final accountIds = [alipay.id, wechat.id, cmb.id];

  // 截图里不留空账户：种子里那个「默认账户」没有交易，删掉
  await (db.delete(db.accounts)
        ..where((t) => t.id.equals('acc-default')))
      .go();

  final now = DateTime.now();
  DateTime at(int daysAgo, int hour, int minute) {
    final day = now.subtract(Duration(days: daysAgo));
    return DateTime(day.year, day.month, day.day, hour, minute);
  }

  final rows = <(int, int, int, int, String, EntryType, String, List<String>)>[
    (0, 12, 30, 3850, '餐饮', EntryType.expense, '公司楼下的牛肉面', ['工作']),
    (0, 9, 12, 1580, '餐饮', EntryType.expense, '瑞幸生椰拿铁', []),
    (0, 8, 5, 300, '交通', EntryType.expense, '地铁', []),
    (1, 19, 40, 23600, '购物', EntryType.expense, '超市采购', ['家庭']),
    (1, 13, 20, 4500, '餐饮', EntryType.expense, '和同事聚餐', ['聚餐']),
    (2, 21, 10, 9800, '娱乐', EntryType.expense, '电影票', []),
    (2, 10, 0, 1200000, '工资', EntryType.income, '九月工资', []),
  ];

  final created = <String>[];
  var accountCursor = 0;
  for (final row in rows) {
    final (daysAgo, hour, minute, cents, categoryName, type, note, tags) = row;
    final result = await repo.create(
      NewTransaction(
        type: type,
        amountCents: cents,
        categoryId: await cat(
          categoryName,
          type == EntryType.income ? CategoryType.income : CategoryType.expense,
        ),
        accountId: accountIds[accountCursor++ % accountIds.length],
        happenedAt: at(daysAgo, hour, minute),
        note: note,
        tags: tags,
      ),
    );
    created.add(result.transactionId);
  }

  final attachmentRepo = attachments;
  if (attachmentRepo == null) return;
  for (var i = 0; i < 2 && i < created.length; i++) {
    await attachmentRepo.add(
      transactionId: created[i],
      bytes: _demoImage,
      fileName: 'demo_receipt_$i.png',
      originalName: 'Screenshot_$i.png',
      sortOrder: i,
    );
  }
}
