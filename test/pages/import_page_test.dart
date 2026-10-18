import 'dart:io';

import 'package:bean_count/data/db/app_database.dart';
import 'package:bean_count/data/db/connection.dart';
import 'package:bean_count/data/repositories/account_repository.dart';
import 'package:bean_count/data/repositories/attachment_repository.dart';
import 'package:bean_count/data/repositories/category_repository.dart';
import 'package:bean_count/data/repositories/transaction_repository.dart';
import 'package:bean_count/pages/import_page.dart';
import 'package:bean_count/pages/settings_page.dart';
import 'package:bean_count/data/repositories/lock_repository.dart';
import 'package:bean_count/data/repositories/recurring_repository.dart';
import 'package:bean_count/services/export/export_service.dart';
import 'package:bean_count/services/import/import_service.dart';
import 'package:bean_count/services/ocr/receipt_vision_settings.dart';
import 'package:bean_count/data/repositories/app_state_repository.dart';
import 'package:bean_count/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late AppDatabase db;
  late Directory tmp;
  late AttachmentRepository attachments;
  late ImportService service;

  setUp(() async {
    db = AppDatabase(openInMemoryConnection());
    tmp = await Directory.systemTemp.createTemp('bean_import_ui');
    final categories = CategoryRepository(db);
    final accounts = AccountRepository(db);
    final transactions = TransactionRepository(db);
    attachments = AttachmentRepository(db, directory: tmp);
    service = ImportService(
      db: db,
      categories: categories,
      accounts: accounts,
      transactions: transactions,
      attachments: attachments,
    );
    await db.select(db.transactions).get();
  });

  tearDown(() async {
    await db.close();
    if (await tmp.exists()) await tmp.delete(recursive: true);
  });

  Future<void> pump(WidgetTester tester, Widget page) async {
    await tester.pumpWidget(
      MaterialApp(theme: buildBeanTheme(Brightness.light), home: page),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
  }

  /// 设置页需要全部依赖，多个用例共用。
  Widget settingsPage() => Scaffold(
        body: SettingsPage(
          importer: service,
          exporter: ExportService(
            transactions: TransactionRepository(db),
            attachments: attachments,
          ),
          categories: CategoryRepository(db),
          accounts: AccountRepository(db),
          recurring: RecurringRepository(db),
          lock: LockRepository(db),
          visionSettings: ReceiptVisionSettingsStore(AppStateRepository(db)),
          visionKeys: MemoryReceiptApiKeyStore(),
        ),
      );

  testWidgets('设置页有导入入口，点开进入导入页', (tester) async {
    await pump(tester, settingsPage());

    expect(find.text('导入账单'), findsOneWidget);
    await tester.tap(find.text('导入账单'));
    await tester.pumpAndSettle();

    expect(find.text('选择账单文件'), findsOneWidget);
    expect(find.textContaining('支持哪些文件'), findsOneWidget);
  });

  testWidgets('设置页有导出入口，点开进入导出页', (tester) async {
    await pump(tester, settingsPage());

    expect(find.text('导出'), findsOneWidget);
    await tester.ensureVisible(find.text('导出'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('导出'));
    await tester.pumpAndSettle();

    expect(find.text('导出 CSV'), findsOneWidget);
    expect(find.text('完整备份 zip'), findsOneWidget);
  });

  testWidgets('设置页有分类与账户入口', (tester) async {
    await pump(tester, settingsPage());

    await tester.tap(find.text('分类'));
    await tester.pumpAndSettle();
    expect(find.text('支出分类'), findsOneWidget);
    await tester.tap(find.byTooltip('返回'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('账户'));
    await tester.pumpAndSettle();
    expect(find.text('默认账户'), findsOneWidget);
  });

  testWidgets('给一份 CSV：预览数字与文件一致', (tester) async {
    final bytes = File('test/fixtures/beecount_sample.csv').readAsBytesSync();

    await tester.pumpWidget(
      MaterialApp(
        theme: buildBeanTheme(Brightness.light),
        home: ImportPage(
          service: service,
          initialBytes: bytes,
          initialName: 'beecount_sample.csv',
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pump(const Duration(milliseconds: 200));

    // 10 行 = 可导入 9 + 跳过 1（转账）
    expect(find.text('可导入'), findsOneWidget);
    expect(find.text('9'), findsWidgets);
    expect(find.textContaining('跳过 1 行'), findsOneWidget);
    expect(find.textContaining('新建 3 个账户'), findsOneWidget);
    expect(find.text('开始导入 9 笔'), findsOneWidget);
  });

  testWidgets('确认导入后显示报告，数字对得上', (tester) async {
    final bytes = File('test/fixtures/beecount_sample.csv').readAsBytesSync();

    await tester.pumpWidget(
      MaterialApp(
        theme: buildBeanTheme(Brightness.light),
        home: ImportPage(
          service: service,
          initialBytes: bytes,
          initialName: 'beecount_sample.csv',
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pump(const Duration(milliseconds: 200));

    await tester.tap(find.text('开始导入 9 笔'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('成功'), findsOneWidget);
    expect(find.text('9'), findsWidgets);
    expect(find.textContaining('新建分类'), findsOneWidget);
    expect(find.text('复制报告'), findsOneWidget);
    expect(await TransactionRepository(db).count(), 9);
  });

  testWidgets('设置页有循环记账入口', (tester) async {
    await pump(tester, settingsPage());

    expect(find.text('循环记账'), findsOneWidget);
    await tester.ensureVisible(find.text('循环记账'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('循环记账'));
    await tester.pumpAndSettle();

    expect(find.textContaining('还没有循环规则'), findsOneWidget);
  });
  testWidgets('设置页有应用锁入口，点开进入设置页', (tester) async {
    await pump(tester, settingsPage());

    expect(find.text('应用锁'), findsOneWidget);
    await tester.ensureVisible(find.text('应用锁'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('应用锁'));
    await tester.pumpAndSettle();

    expect(find.text('已关闭'), findsOneWidget);
    expect(find.text('开启应用锁'), findsOneWidget);
  });
}