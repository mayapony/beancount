import 'package:bean_count/data/db/app_database.dart';
import 'package:bean_count/data/db/connection.dart';
import 'package:bean_count/data/repositories/lock_repository.dart';
import 'package:bean_count/data/repositories/theme_repository.dart';
import 'package:bean_count/main.dart';
import 'package:bean_count/theme/theme_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

/// 真机/模拟器：设置里切深色 → 立即变暗 → 重建 App（模拟冷启动）后仍是深色。
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('切深色立即生效，重建后保持', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.75;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final db = AppDatabase(openInMemoryConnection());
    await db.select(db.appState).get();
    final controller = ThemeController(repository: ThemeRepository(db));

    Future<void> pumpApp() async {
      await tester.pumpWidget(
        BeanApp(
          database: db,
          themeController: controller,
          lockRepository: LockRepository(db),
        ),
      );
      await tester.pumpAndSettle();
    }

    // 先把主题固定成浅色，避免受模拟器当前系统深色影响
    await controller.setThemeMode(ThemeMode.light);
    await pumpApp();
    expect(
      Theme.of(tester.element(find.byType(Scaffold).first)).brightness,
      Brightness.light,
    );

    // 设置 → 主题 → 深色
    await tester.tap(find.text('设置').last);
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('主题'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('主题'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('深色'));
    await tester.pumpAndSettle();

    expect(controller.mode, ThemeMode.dark);
    expect(
      Theme.of(tester.element(find.byType(Scaffold).first)).brightness,
      Brightness.dark,
    );
    expect(find.text('深色'), findsOneWidget, reason: '设置页行尾显示当前档位');

    // 模拟冷启动：同一份库重新读偏好
    final coldStart = ThemeController(repository: ThemeRepository(db));
    await coldStart.load();
    await tester.pumpWidget(
      BeanApp(
        database: db,
        themeController: coldStart,
        lockRepository: LockRepository(db),
      ),
    );
    await tester.pumpAndSettle();
    expect(coldStart.mode, ThemeMode.dark);
    expect(
      Theme.of(tester.element(find.byType(Scaffold).first)).brightness,
      Brightness.dark,
      reason: '冷启动首帧就是深色',
    );

    await db.close();
  });
}
