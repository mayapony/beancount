import 'package:bean_count/data/db/app_database.dart';
import 'package:bean_count/data/db/connection.dart';
import 'package:bean_count/data/repositories/lock_repository.dart';
import 'package:bean_count/pages/app_lock_page.dart';
import 'package:bean_count/pages/lock_screen.dart';
import 'package:bean_count/theme/app_theme.dart';
import 'package:bean_count/widgets/lock_gate.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late AppDatabase db;
  late LockRepository lock;

  setUp(() async {
    db = AppDatabase(openInMemoryConnection());
    lock = LockRepository(db);
    await db.select(db.appState).get();
  });

  tearDown(() async => db.close());

  Future<void> pump(WidgetTester tester, Widget child) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.75;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(theme: buildBeanTheme(Brightness.light), home: child),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
  }

  Future<void> tapDigits(WidgetTester tester, String pin) async {
    for (final digit in pin.split('')) {
      await tester.tap(find.text(digit).last);
      await tester.pump();
    }
    await tester.pump(const Duration(milliseconds: 50));
  }

  group('LockScreen', () {
    testWidgets('输对解锁，输错提示并清空', (tester) async {
      var unlocked = false;
      await pump(
        tester,
        LockScreen(
          length: 4,
          onVerify: (pin) async => pin == '1234',
          onUnlocked: () => unlocked = true,
        ),
      );

      await tapDigits(tester, '9999');
      expect(find.textContaining('PIN 不正确'), findsOneWidget);
      expect(unlocked, isFalse);

      await tapDigits(tester, '1234');
      expect(unlocked, isTrue);
    });

    testWidgets('连续 5 次错误后限速，超时恢复', (tester) async {
      var now = DateTime(2026, 10, 18, 12);
      await pump(
        tester,
        LockScreen(
          length: 4,
          now: () => now,
          onVerify: (_) async => false,
          onUnlocked: () {},
        ),
      );

      for (var i = 0; i < 5; i++) {
        await tapDigits(tester, '0000');
      }
      expect(find.textContaining('秒后再试'), findsOneWidget);

      // 锁定期间输入无效：再点也不会触发校验
      await tapDigits(tester, '0000');
      expect(find.textContaining('秒后再试'), findsOneWidget);

      now = now.add(const Duration(seconds: 31));
      await tester.pump(const Duration(seconds: 1));
      expect(find.textContaining('秒后再试'), findsNothing);
    });

    testWidgets('正确解锁后错误计数归零', (tester) async {
      await pump(
        tester,
        LockScreen(
          length: 4,
          onVerify: (pin) async => pin == '1234',
          onUnlocked: () {},
        ),
      );

      await tapDigits(tester, '0000');
      await tapDigits(tester, '0000');
      expect(find.textContaining('还可尝试 3 次'), findsOneWidget);

      await tapDigits(tester, '1234');
      expect(find.textContaining('还可尝试'), findsNothing);
    });
  });

  group('LockGate', () {
    testWidgets('未开启锁：直接显示内容', (tester) async {
      await pump(
        tester,
        LockGate(repository: lock, child: const Text('账本内容')),
      );
      expect(find.text('账本内容'), findsOneWidget);
      expect(find.text('输入 PIN 解锁'), findsNothing);
    });

    testWidgets('已开启：先锁屏，输对后进入', (tester) async {
      await lock.setPin('1234');
      await pump(
        tester,
        LockGate(repository: lock, child: const Text('账本内容')),
      );

      expect(find.text('输入 PIN 解锁'), findsOneWidget);
      expect(find.text('账本内容'), findsNothing);

      await tapDigits(tester, '1234');
      expect(find.text('账本内容'), findsOneWidget);
    });

    testWidgets('后台超过宽限期后重新上锁', (tester) async {
      await lock.setPin('1234');
      var now = DateTime(2026, 10, 18, 12);

      await pump(
        tester,
        LockGate(
          repository: lock,
          now: () => now,
          gracePeriod: const Duration(minutes: 1),
          child: const Text('账本内容'),
        ),
      );
      await tapDigits(tester, '1234');
      expect(find.text('账本内容'), findsOneWidget);

      // 切走 10 秒回来：不打扰
      final gate = tester.state<State>(find.byType(LockGate));
      (gate as dynamic).didChangeAppLifecycleState(AppLifecycleState.paused);
      now = now.add(const Duration(seconds: 10));
      (gate as dynamic).didChangeAppLifecycleState(AppLifecycleState.resumed);
      await tester.pump();
      expect(find.text('账本内容'), findsOneWidget);

      // 再切走 2 分钟回来：重新上锁
      (gate as dynamic).didChangeAppLifecycleState(AppLifecycleState.paused);
      now = now.add(const Duration(minutes: 2));
      (gate as dynamic).didChangeAppLifecycleState(AppLifecycleState.resumed);
      await tester.pump();
      expect(find.text('输入 PIN 解锁'), findsOneWidget);
    });
  });

  group('AppLockPage', () {
    Future<void> enterPin(WidgetTester tester, String pin) async {
      await tester.enterText(find.byType(TextField), pin);
      await tester.tap(find.text('确定'));
      await tester.pumpAndSettle();
    }

    testWidgets('开启：两次输入一致后生效', (tester) async {
      await pump(tester, AppLockPage(repository: lock));
      expect(find.text('开启应用锁'), findsOneWidget);

      await tester.tap(find.text('开启应用锁'));
      await tester.pumpAndSettle();
      await enterPin(tester, '1234');
      await enterPin(tester, '1234');

      expect(find.text('已开启'), findsOneWidget);
      expect(await lock.isEnabled(), isTrue);
      expect(await lock.verify('1234'), isTrue);
    });

    testWidgets('两次不一致不生效', (tester) async {
      await pump(tester, AppLockPage(repository: lock));

      await tester.tap(find.text('开启应用锁'));
      await tester.pumpAndSettle();
      await enterPin(tester, '1234');
      await enterPin(tester, '9999');

      expect(find.textContaining('两次输入不一致'), findsOneWidget);
      expect(await lock.isEnabled(), isFalse);
    });

    testWidgets('关闭：需要当前 PIN，错 PIN 不关闭', (tester) async {
      await lock.setPin('1234');
      await pump(tester, AppLockPage(repository: lock));
      expect(find.text('已开启'), findsOneWidget);

      await tester.tap(find.text('关闭应用锁'));
      await tester.pumpAndSettle();
      await enterPin(tester, '0000');
      expect(find.text('PIN 不正确'), findsOneWidget);
      expect(await lock.isEnabled(), isTrue);

      await tester.tap(find.text('关闭应用锁'));
      await tester.pumpAndSettle();
      await enterPin(tester, '1234');
      expect(find.text('已关闭'), findsOneWidget);
      expect(await lock.isEnabled(), isFalse);
    });
  });
}
