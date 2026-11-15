import 'package:bean_count/data/db/app_database.dart';
import 'package:bean_count/data/db/connection.dart';
import 'package:bean_count/data/repositories/app_state_repository.dart';
import 'package:bean_count/data/repositories/lock_repository.dart';
import 'package:bean_count/pages/shell.dart';
import 'package:bean_count/services/ocr/receipt_guess.dart';
import 'package:bean_count/services/ocr/receipt_vision_settings.dart';
import 'package:bean_count/services/screenshot/pending_entry.dart';
import 'package:bean_count/services/screenshot/screenshot_settings.dart';
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
    // 首帧后还要等 pending 的异步读库与提示动画
    for (var i = 0; i < 4; i++) {
      await tester.pump(const Duration(milliseconds: 120));
    }
    await tester.pumpAndSettle();
  }

  Future<void> addGuess({
    String id = 'shot-1',
    DateTime? at,
    int amount = 4450,
    String? error,
    ReceiptGuess? guess,
  }) {
    return pending.add(
      PendingScreenshotEntry(
        id: id,
        createdAt: at ?? DateTime.now(),
        guess: guess ??
            const ReceiptGuess(
              amountCents: 4450,
              categoryName: '餐饮',
              note: '金豆餐厅',
              confidence: ReceiptConfidence.amount,
            ),
        error: error,
      ),
    );
  }

  testWidgets('新鲜的一条只给一条汇总提示，不自动打开面板', (tester) async {
    await addGuess();
    await pumpShell(tester);

    expect(find.text('有 1 张截图没能自动记账'), findsOneWidget);
    expect(find.text('记一笔'), findsNothing);
    expect(await pending.peek(), isNull);
  });

  testWidgets('多条新鲜的合并成一条提示，不逐条弹出', (tester) async {
    await addGuess(id: 'shot-a');
    await addGuess(id: 'shot-b');
    await addGuess(id: 'shot-c');
    await pumpShell(tester);

    expect(find.text('有 3 张截图没能自动记账'), findsOneWidget);
    expect(find.text('记一笔'), findsNothing);
    expect(await pending.count(), 0);
  });

  testWidgets('过期的待处理不再提示，队列照样清空', (tester) async {
    final stale = DateTime.now().subtract(const Duration(minutes: 30));
    await addGuess(id: 'old-a', at: stale);
    await addGuess(id: 'old-b', at: stale);
    await addGuess(id: 'old-c', at: stale);
    await addGuess(id: 'new-a');
    await addGuess(id: 'new-b');
    await pumpShell(tester);

    // 只提示本轮还新鲜的这两条
    expect(find.text('有 2 张截图没能自动记账'), findsOneWidget);
    expect(find.textContaining('5'), findsNothing);
    expect(await pending.count(), 0);
  });

  testWidgets('全部过期时一条提示都不弹', (tester) async {
    final stale = DateTime.now().subtract(const Duration(hours: 2));
    await addGuess(id: 'old-a', at: stale);
    await addGuess(id: 'old-b', at: stale);
    await pumpShell(tester);

    expect(find.textContaining('没能自动记账'), findsNothing);
    expect(await pending.count(), 0);
  });

  testWidgets('识别失败也给汇总提示，不逐条报原因', (tester) async {
    await pending.write(
      PendingScreenshotEntry(
        id: 'shot-2',
        createdAt: DateTime.now(),
        error: '识别超时，稍后再试',
      ),
    );
    await pumpShell(tester);

    expect(find.text('有 1 张截图没能自动记账'), findsOneWidget);
    expect(find.text('识别超时，稍后再试'), findsNothing);
    expect(find.text('记一笔'), findsNothing);
  });

  testWidgets('没有识别结果时提示不带补记入口', (tester) async {
    await pending.write(
      PendingScreenshotEntry(
        id: 'shot-3',
        createdAt: DateTime.now(),
        error: '没认出金额',
      ),
    );
    await pumpShell(tester);

    expect(find.text('补记'), findsNothing);
  });

  testWidgets('点「补记」用最新的识别结果打开面板', (tester) async {
    await addGuess(id: 'shot-a', amount: 3002);
    await pumpShell(tester);

    await tester.tap(find.text('补记'));
    await tester.pumpAndSettle();

    expect(find.text('记一笔'), findsOneWidget);
    expect(find.text('44.50'), findsWidgets);
  });

  testWidgets('应用锁开启时先解锁，解锁后才提示', (tester) async {
    final lock = LockRepository(db);
    await lock.setPin('1234');
    await addGuess();

    await pumpShell(
      tester,
      home: LockGate(
        repository: lock,
        child: ShellPage(database: db, visionKeys: MemoryReceiptApiKeyStore()),
      ),
    );

    expect(find.text('输入 PIN 解锁'), findsOneWidget);
    expect(find.text('有 1 张截图没能自动记账'), findsNothing);

    for (final digit in '1234'.split('')) {
      await tester.tap(find.text(digit).last);
      await tester.pump();
    }
    for (var i = 0; i < 4; i++) {
      await tester.pump(const Duration(milliseconds: 120));
    }
    await tester.pumpAndSettle();

    expect(find.text('有 1 张截图没能自动记账'), findsOneWidget);
    expect(await pending.peek(), isNull);
  });

  testWidgets('补记时开启自动新建，词表内的新分类显示为候选', (tester) async {
    await screenshotSettings.save(
      const ScreenshotSettings(autoEntry: true, autoCreateCategories: true),
    );
    await addGuess(
      guess: const ReceiptGuess(
        amountCents: 3800,
        categoryName: '咖啡',
        confidence: ReceiptConfidence.amount,
      ),
    );
    await pumpShell(tester);

    await tester.tap(find.text('补记'));
    await tester.pumpAndSettle();

    expect(find.textContaining('将新建分类「咖啡」'), findsOneWidget);
  });
}
