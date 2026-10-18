import 'package:bean_count/data/db/app_database.dart';
import 'package:bean_count/data/db/connection.dart';
import 'package:bean_count/data/repositories/app_state_repository.dart';
import 'package:bean_count/services/screenshot/screenshot_settings.dart';
import 'package:bean_count/theme/app_theme.dart';
import 'package:bean_count/widgets/screenshot_settings_section.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late AppDatabase db;
  late AppStateRepository state;
  late ScreenshotSettingsStore store;

  setUp(() async {
    db = AppDatabase(openInMemoryConnection());
    state = AppStateRepository(db);
    store = ScreenshotSettingsStore(state);
    await db.select(db.appState).get();
  });

  tearDown(() async => db.close());

  Widget harness({
    ScreenshotPermissionRequest? requestPermissions,
    ValueChanged<bool>? onAutoEntryChanged,
  }) {
    return MaterialApp(
      theme: buildBeanTheme(Brightness.light),
      home: Scaffold(
        body: ListView(
          children: [
            ScreenshotSettingsSection(
              store: store,
              requestPermissions: requestPermissions,
              onAutoEntryChanged: onAutoEntryChanged,
            ),
          ],
        ),
      ),
    );
  }

  SwitchListTile tile(WidgetTester tester, String key) =>
      tester.widget<SwitchListTile>(find.byKey(Key(key)));

  testWidgets('默认三个开关都关闭，不显示权限提示', (tester) async {
    await tester.pumpWidget(harness());
    await tester.pumpAndSettle();

    expect(tile(tester, 'screenshot-auto-entry-switch').value, isFalse);
    expect(tile(tester, 'auto-create-categories-switch').value, isFalse);
    expect(tile(tester, 'auto-tags-switch').value, isFalse);
    expect(find.byKey(const Key('screenshot-permission-hint')), findsNothing);
  });

  testWidgets('授权通过后开启总开关并显示权限说明', (tester) async {
    final changes = <bool>[];
    await tester.pumpWidget(harness(
      requestPermissions: () async => true,
      onAutoEntryChanged: changes.add,
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('screenshot-auto-entry-switch')));
    await tester.pumpAndSettle();

    expect(tile(tester, 'screenshot-auto-entry-switch').value, isTrue);
    expect(find.byKey(const Key('screenshot-permission-hint')), findsOneWidget);
    expect(changes, [true]);
    expect((await store.load()).autoEntry, isTrue);
  });

  testWidgets('拒绝权限时保持关闭并说明原因', (tester) async {
    final changes = <bool>[];
    await tester.pumpWidget(harness(
      requestPermissions: () async => false,
      onAutoEntryChanged: changes.add,
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('screenshot-auto-entry-switch')));
    await tester.pumpAndSettle();

    expect(tile(tester, 'screenshot-auto-entry-switch').value, isFalse);
    expect(find.textContaining('未授权相册读取或通知'), findsOneWidget);
    expect(changes, [false]);
    expect((await store.load()).autoEntry, isFalse);
  });

  testWidgets('自动新建分类与标签开关会持久化', (tester) async {
    await tester.pumpWidget(harness());
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('auto-create-categories-switch')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('auto-tags-switch')));
    await tester.pumpAndSettle();

    final saved = await store.load();
    expect(saved.autoCreateCategories, isTrue);
    expect(saved.autoTags, isTrue);
  });

  testWidgets('重新打开时读取已保存的开关', (tester) async {
    await store.save(const ScreenshotSettings(autoEntry: true, autoTags: true));

    await tester.pumpWidget(harness());
    await tester.pumpAndSettle();

    expect(tile(tester, 'screenshot-auto-entry-switch').value, isTrue);
    expect(tile(tester, 'auto-tags-switch').value, isTrue);
  });
}
