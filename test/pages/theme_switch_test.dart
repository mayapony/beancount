import 'dart:io';

import 'package:bean_count/data/db/app_database.dart';
import 'package:bean_count/data/db/connection.dart';
import 'package:bean_count/data/repositories/account_repository.dart';
import 'package:bean_count/data/repositories/attachment_repository.dart';
import 'package:bean_count/data/repositories/category_repository.dart';
import 'package:bean_count/data/repositories/lock_repository.dart';
import 'package:bean_count/data/repositories/recurring_repository.dart';
import 'package:bean_count/data/repositories/theme_repository.dart';
import 'package:bean_count/main.dart';
import 'package:bean_count/pages/settings_page.dart';
import 'package:bean_count/services/export/export_service.dart';
import 'package:bean_count/services/import/import_service.dart';
import 'package:bean_count/data/repositories/transaction_repository.dart';
import 'package:bean_count/theme/app_theme.dart';
import 'package:bean_count/theme/theme_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late AppDatabase db;
  late ThemeController controller;

  setUp(() async {
    db = AppDatabase(openInMemoryConnection());
    await db.select(db.appState).get();
    controller = ThemeController(repository: ThemeRepository(db));
  });

  tearDown(() async => db.close());

  Widget settingsPage() => MaterialApp(
        theme: buildBeanTheme(Brightness.light),
        home: Scaffold(
          body: SettingsPage(
            theme: controller,
            importer: ImportService(
              db: db,
              categories: CategoryRepository(db),
              accounts: AccountRepository(db),
              transactions: TransactionRepository(db),
              attachments: AttachmentRepository(db, directory: Directory.systemTemp),
            ),
            exporter: ExportService(
              transactions: TransactionRepository(db),
              attachments: AttachmentRepository(db, directory: Directory.systemTemp),
            ),
            categories: CategoryRepository(db),
            accounts: AccountRepository(db),
            recurring: RecurringRepository(db),
            lock: LockRepository(db),
          ),
        ),
      );

  testWidgets('主题行显示当前档位，选择深色后立即更新', (tester) async {
    await tester.pumpWidget(settingsPage());
    await tester.pump();

    expect(find.text('跟随系统'), findsOneWidget);

    await tester.tap(find.text('主题'));
    await tester.pumpAndSettle();

    // 面板里三档都在，当前项有勾
    expect(find.text('浅色'), findsOneWidget);
    expect(find.text('深色'), findsOneWidget);
    expect(find.byIcon(Icons.check_rounded), findsOneWidget);

    await tester.tap(find.text('深色'));
    await tester.pumpAndSettle();

    expect(controller.mode, ThemeMode.dark);
    expect(find.text('深色'), findsOneWidget, reason: '行尾换成深色');
    expect(await ThemeRepository(db).load(), ThemeMode.dark);
  });

  testWidgets('App 跟随控制器切换主题', (tester) async {
    await tester.pumpWidget(
      BeanApp(
        database: db,
        themeController: controller,
        lockRepository: LockRepository(db),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    MaterialApp app() => tester.widget<MaterialApp>(find.byType(MaterialApp));
    expect(app().themeMode, ThemeMode.system);

    await controller.setThemeMode(ThemeMode.dark);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(app().themeMode, ThemeMode.dark);
    // 深色主题真的被选中了
    final context = tester.element(find.byType(Scaffold).first);
    expect(Theme.of(context).brightness, Brightness.dark);

    await controller.setThemeMode(ThemeMode.light);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    final context2 = tester.element(find.byType(Scaffold).first);
    expect(Theme.of(context2).brightness, Brightness.light);
  });
}
