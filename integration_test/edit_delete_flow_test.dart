import 'dart:io';

import 'package:bean_count/data/db/app_database.dart';
import 'package:bean_count/data/db/connection.dart';
import 'package:bean_count/data/db/enums.dart';
import 'package:bean_count/data/repositories/attachment_repository.dart';
import 'package:bean_count/data/repositories/category_repository.dart';
import 'package:bean_count/data/repositories/transaction_repository.dart';
import 'package:bean_count/pages/shell.dart';
import 'package:bean_count/pages/transaction_detail_page.dart';
import 'package:bean_count/theme/app_theme.dart';
import 'package:bean_count/utils/month.dart';
import 'package:bean_count/widgets/month_picker_sheet.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// 真机/模拟器上的端到端：切月、编辑、删除在真实数据库与真实文件系统上成立。
///
/// 运行：flutter test integration_test/edit_delete_flow_test.dart -d emulator-5554
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;
  late Directory attachmentDir;

  setUp(() async {
    db = AppDatabase(openInMemoryConnection());
    attachmentDir = await Directory(
      p.join((await getApplicationDocumentsDirectory()).path, 'it_attachments'),
    ).create(recursive: true);
  });

  tearDown(() async {
    await db.close();
    if (await attachmentDir.exists()) await attachmentDir.delete(recursive: true);
  });

  testWidgets('切月 → 编辑 → 删除，全部在真实设备上跑通', (tester) async {
    final categories = CategoryRepository(db);
    final transactions = TransactionRepository(db);
    final attachments =
        AttachmentRepository(db, directory: attachmentDir);
    await db.select(db.transactions).get();

    final food = (await categories.findByName('餐饮', CategoryType.expense))!;
    final transport =
        (await categories.findByName('交通', CategoryType.expense))!;

    final current = LedgerMonth.current();
    final previous = current.previous;

    await transactions.create(
      NewTransaction(
        type: EntryType.expense,
        amountCents: 2200,
        categoryId: food.id,
        happenedAt: DateTime.now(),
        note: '当月牛肉面',
      ),
    );
    final lastMonth = await transactions.create(
      NewTransaction(
        type: EntryType.expense,
        amountCents: 1500,
        categoryId: food.id,
        happenedAt: DateTime(previous.year, previous.month, 12, 9),
        note: '上月地铁',
      ),
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: buildBeanTheme(Brightness.light),
        home: Scaffold(
          body: ShellPage(database: db, attachmentRepository: attachments),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // 当月
    expect(find.text('当月牛肉面'), findsOneWidget);

    // 切到上个月
    await tester.tap(find.byIcon(Icons.calendar_month_rounded));
    await tester.pumpAndSettle();
    await tester.tap(
      find.descendant(
        of: find.byType(MonthPickerSheet),
        matching: find.text('${previous.month}月'),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('上月地铁'), findsOneWidget);
    expect(find.text('当月牛肉面'), findsNothing);

    // 进详情，改分类为「交通」
    await tester.tap(find.text('上月地铁'));
    await tester.pumpAndSettle();
    expect(find.byType(TransactionDetailPage), findsOneWidget);
    await tester.tap(find.text('编辑'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('交通'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('完成').last);
    await tester.pumpAndSettle();
    expect(find.text('交通'), findsWidgets);

    final edited = await transactions.byId(lastMonth.transactionId);
    expect(edited!.category.name, '交通');
    expect(edited.amountCents, 1500);

    // 删除这一笔，回到明细后该行消失
    await tester.tap(find.text('删除这笔'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('删除'));
    await tester.pumpAndSettle();
    expect(find.byType(TransactionDetailPage), findsNothing);
    expect(find.text('上月地铁'), findsNothing);
    expect(await transactions.byId(lastMonth.transactionId), isNull);

    // 回到本月仍能看到当月那笔
    await tester.tap(find.byIcon(Icons.calendar_month_rounded));
    await tester.pumpAndSettle();
    await tester.tap(find.text('回到本月'));
    await tester.pumpAndSettle();
    expect(find.text('当月牛肉面'), findsOneWidget);
    expect(transport.id, isNotEmpty);
  });

  test('编辑与删除落盘后，重开数据库仍是新值', () async {
    final dir = await getApplicationDocumentsDirectory();
    final file = File(p.join(dir.path, 'it_persist.sqlite'));
    if (await file.exists()) await file.delete();

    AppDatabase open() => AppDatabase(NativeDatabase(file));

    final db1 = open();
    final categories = CategoryRepository(db1);
    final repo = TransactionRepository(db1);
    await db1.select(db1.transactions).get();

    final created = await repo.create(
      NewTransaction(
        type: EntryType.expense,
        amountCents: 1000,
        categoryId: (await categories.findByName('餐饮', CategoryType.expense))!
            .id,
        happenedAt: DateTime(2026, 10, 17, 12),
        note: '重启前',
      ),
    );
    await repo.update(
      created.transactionId,
      TransactionEdit(
        type: EntryType.expense,
        amountCents: 2500,
        categoryId: (await categories.findByName('交通', CategoryType.expense))!
            .id,
        happenedAt: DateTime(2026, 10, 17, 12),
        note: '改过之后',
      ),
    );
    final toDelete = await repo.create(
      NewTransaction(
        type: EntryType.expense,
        amountCents: 800,
        categoryId: (await categories.findByName('餐饮', CategoryType.expense))!
            .id,
        happenedAt: DateTime(2026, 10, 16, 12),
        note: '待删除',
      ),
    );
    await repo.delete(toDelete.transactionId);
    await db1.close();

    // 重开：编辑生效、删除生效
    final db2 = open();
    final reopened = TransactionRepository(db2);
    final row = await reopened.byId(created.transactionId);
    expect(row, isNotNull);
    expect(row!.amountCents, 2500);
    expect(row.category.name, '交通');
    expect(row.transaction.note, '改过之后');
    expect(await reopened.byId(toDelete.transactionId), isNull);
    expect(await reopened.count(), 1);
    await db2.close();

    if (await file.exists()) await file.delete();
  });
}
