import 'package:bean_count/data/db/app_database.dart';
import 'package:bean_count/data/db/connection.dart';
import 'package:bean_count/data/repositories/lock_repository.dart';
import 'package:bean_count/pages/shell.dart';
import 'package:bean_count/theme/app_theme.dart';
import 'package:bean_count/widgets/lock_gate.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

/// 真机/模拟器：应用锁闸门在真实引擎上拦住入口、输对才放行、关掉后不再拦。
///
/// 运行：flutter test integration_test/lock_flow_test.dart -d emulator-5554
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  Future<void> pumpApp(WidgetTester tester, Widget home) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.75;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(theme: buildBeanTheme(Brightness.light), home: home),
    );
    await tester.pumpAndSettle();
  }

  Future<void> tapPin(WidgetTester tester, String pin) async {
    for (final digit in pin.split('')) {
      await tester.tap(find.text(digit).last);
      await tester.pump(const Duration(milliseconds: 40));
    }
    await tester.pumpAndSettle();
  }

  testWidgets('开启 PIN 后锁屏拦截；输错被拒；输对进入；关闭后直接进入', (tester) async {
    final db = AppDatabase(openInMemoryConnection());
    final lock = LockRepository(db);
    await db.select(db.appState).get();
    await lock.setPin('1234');

    await pumpApp(
      tester,
      LockGate(
        repository: lock,
        child: ShellPage(database: db),
      ),
    );

    // 锁屏挡住入口
    expect(find.text('输入 PIN 解锁'), findsOneWidget);
    expect(find.text('明细'), findsNothing);

    // 输错
    await tapPin(tester, '0000');
    expect(find.textContaining('PIN 不正确'), findsOneWidget);
    expect(find.text('明细'), findsNothing);

    // 输对
    await tapPin(tester, '1234');
    expect(find.text('明细'), findsWidgets);

    // 关闭应用锁后重新挂载：不再拦截
    await lock.disable();
    await pumpApp(
      tester,
      LockGate(
        repository: lock,
        child: ShellPage(database: db),
      ),
    );
    expect(find.text('输入 PIN 解锁'), findsNothing);
    expect(find.text('明细'), findsWidgets);

    await db.close();
  });
}
