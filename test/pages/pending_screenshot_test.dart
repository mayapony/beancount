import 'package:bean_count/data/db/app_database.dart';
import 'package:bean_count/data/db/connection.dart';
import 'package:bean_count/data/repositories/lock_repository.dart';
import 'package:bean_count/pages/shell.dart';
import 'package:bean_count/services/ocr/receipt_guess.dart';
import 'package:bean_count/services/ocr/receipt_vision_settings.dart';
import 'package:bean_count/services/screenshot/pending_entry.dart';
import 'package:bean_count/services/screenshot/screenshot_settings.dart';
import 'package:bean_count/data/repositories/app_state_repository.dart';
import 'package:bean_count/theme/app_theme.dart';
import 'package:bean_count/widgets/lock_gate.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late AppDatabase db;
  late PendingScreenshotEntryStore pending;
  late ScreenshotSettingsStore screenshotSettings;

  setUp(() async {
    db = AppDatabase(openInMemoryConnection());
    final state = AppStateRepository(db);
    pending = PendingScreenshotEntryStore(state);
    screenshotSettings = ScreenshotSettingsStore(state);
    await db.select(db.appState).get(); // 触发建库与种子
  });

  tearDown(() async => db.close());

  Future<void> pumpShell(WidgetTester tester, {Widget? home}) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.75;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        theme: buildBeanTheme(Brightness.light),
        home: home ??
            ShellPage(
              database: db,
              visionKeys: MemoryReceiptApiKeyStore(),
            ),
      ),
    );
    // 首帧后还要等 pending 的异步读库与面板动画
    for (var i = 0; i < 4; i++) {
      await tester.pump(const Duration(milliseconds: 120));
    }
    await tester.pumpAndSettle();
  }

  Future<void> writeGuess() => pending.write(
        PendingScreenshotEntry(
          id: 'shot-1',
          createdAt: DateTime(2026, 10, 18, 12),
          guess: const ReceiptGuess(
            amountCents: 4450,
            categoryName: '餐饮',
            note: '金豆餐厅',
            confidence: ReceiptConfidence.amount,
          ),
        ),
      );

  testWidgets('冷启动读取 pending 并打开预填面板，随后清空', (tester) async {
    await writeGuess();
    await pumpShell(tester);

    expect(find.text('记一笔'), findsOneWidget);
    expect(find.text('44.50'), findsWidgets);
    expect(find.textContaining('金豆餐厅'), findsWidgets);
    expect(await pending.peek(), isNull);
  });

  testWidgets('同一条 pending 不会在下次启动时重复弹出', (tester) async {
    await writeGuess();
    await pumpShell(tester);
    expect(find.text('记一笔'), findsOneWidget);

    // 关掉面板再重建整棵树，模拟下一次冷启动
    await tester.tap(find.byTooltip('关闭'));
    await tester.pumpAndSettle();
    await pumpShell(tester);

    expect(find.text('记一笔'), findsNothing);
  });

  testWidgets('识别失败时显示真实原因，不打开面板', (tester) async {
    await pending.write(
      PendingScreenshotEntry(
        id: 'shot-2',
        createdAt: DateTime(2026, 10, 18, 12),
        error: '识别超时，稍后再试',
      ),
    );
    await pumpShell(tester);

    expect(find.text('识别超时，稍后再试'), findsOneWidget);
    expect(find.text('记一笔'), findsNothing);
  });

  testWidgets('应用锁开启时先解锁，解锁后才弹面板', (tester) async {
    final lock = LockRepository(db);
    await lock.setPin('1234');
    await writeGuess();

    await pumpShell(
      tester,
      home: LockGate(
        repository: lock,
        child: ShellPage(database: db, visionKeys: MemoryReceiptApiKeyStore()),
      ),
    );

    expect(find.text('输入 PIN 解锁'), findsOneWidget);
    expect(find.text('记一笔'), findsNothing);

    for (final digit in '1234'.split('')) {
      await tester.tap(find.text(digit).last);
      await tester.pump();
    }
    for (var i = 0; i < 4; i++) {
      await tester.pump(const Duration(milliseconds: 120));
    }
    await tester.pumpAndSettle();

    expect(find.text('记一笔'), findsOneWidget);
    expect(await pending.peek(), isNull);
  });

  testWidgets('开启自动新建后，词表内的新分类显示为候选', (tester) async {
    await screenshotSettings.save(
      const ScreenshotSettings(autoEntry: true, autoCreateCategories: true),
    );
    await pending.write(
      PendingScreenshotEntry(
        id: 'shot-3',
        createdAt: DateTime(2026, 10, 18, 12),
        guess: const ReceiptGuess(
          amountCents: 3800,
          categoryName: '咖啡',
          confidence: ReceiptConfidence.amount,
        ),
      ),
    );
    await pumpShell(tester);

    expect(find.textContaining('将新建分类「咖啡」'), findsOneWidget);
  });
}
