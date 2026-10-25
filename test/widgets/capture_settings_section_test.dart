import 'package:bean_count/data/db/app_database.dart';
import 'package:bean_count/data/db/connection.dart';
import 'package:bean_count/data/repositories/app_state_repository.dart';
import 'package:bean_count/services/capture/capture_channel.dart';
import 'package:bean_count/services/capture/capture_settings.dart';
import 'package:bean_count/theme/app_theme.dart';
import 'package:bean_count/widgets/capture_settings_section.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakePlatform implements CapturePlatform {
  bool supported = true;
  bool accessibility = false;
  bool notification = false;
  bool enabled = false;
  int openAccessibilityCalls = 0;

  @override
  bool get isSupported => supported;

  @override
  Future<bool> setEnabled(bool value) async {
    enabled = value;
    return true;
  }

  @override
  Future<bool> isAccessibilityEnabled() async => accessibility;

  @override
  Future<bool> isNotificationListenerEnabled() async => notification;

  @override
  Future<void> openAccessibilitySettings() async {
    openAccessibilityCalls++;
  }

  @override
  Future<void> openNotificationListenerSettings() async {}

  @override
  Future<bool> takeOpenAutoEntries() async => false;

  @override
  void setNativeListeners({Future<void> Function()? onOpenAutoEntries}) {}
}

void main() {
  late AppDatabase db;
  late CaptureSettingsStore store;
  late _FakePlatform platform;

  setUp(() async {
    db = AppDatabase(openInMemoryConnection());
    store = CaptureSettingsStore(AppStateRepository(db));
    platform = _FakePlatform();
    await db.select(db.appState).get();
  });

  tearDown(() async => db.close());

  Widget harness() {
    return MaterialApp(
      theme: buildBeanTheme(Brightness.light),
      home: Scaffold(
        body: ListView(
          children: [
            CaptureSettingsSection(
              store: store,
              platform: platform,
              onOpenAutoEntries: () {},
            ),
          ],
        ),
      ),
    );
  }

  SwitchListTile tile(WidgetTester tester) =>
      tester.widget<SwitchListTile>(find.byKey(const Key('capture-auto-entry-switch')));

  testWidgets('默认关闭，不显示授权引导与列表入口', (tester) async {
    await tester.pumpWidget(harness());
    await tester.pumpAndSettle();

    expect(tile(tester).value, isFalse);
    expect(find.byKey(const Key('capture-permission-hint')), findsNothing);
    expect(find.byKey(const Key('capture-auto-entries-entry')), findsNothing);
  });

  testWidgets('开启后显示授权引导、状态行与列表入口，并持久化', (tester) async {
    await tester.pumpWidget(harness());
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('capture-auto-entry-switch')));
    await tester.pumpAndSettle();

    expect(tile(tester).value, isTrue);
    expect(find.byKey(const Key('capture-permission-hint')), findsOneWidget);
    expect(find.byKey(const Key('capture-auto-entries-entry')), findsOneWidget);
    expect(find.textContaining('无障碍权限'), findsOneWidget);
    expect(find.textContaining('通知使用权 ·'), findsOneWidget);
    expect((await store.load()).enabled, isTrue);
    expect(platform.enabled, isTrue);
  });

  testWidgets('授权状态反映在状态行', (tester) async {
    platform.accessibility = true;
    platform.notification = false;
    await store.setEnabled(true);

    await tester.pumpWidget(harness());
    await tester.pumpAndSettle();

    expect(find.textContaining('无障碍权限 · 已开启'), findsOneWidget);
    expect(find.textContaining('通知使用权 · 未开启'), findsOneWidget);
  });

  testWidgets('连续 7 天零捕获显示失效提示', (tester) async {
    await store.save(CaptureSettings(
      enabled: true,
      lastCaptureAt: DateTime.now().subtract(const Duration(days: 8)),
    ));

    await tester.pumpWidget(harness());
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('capture-stale-hint')), findsOneWidget);
    expect(find.textContaining('自动记账可能已失效'), findsOneWidget);
  });

  testWidgets('恢复捕获后失效提示消失', (tester) async {
    await store.save(CaptureSettings(
      enabled: true,
      lastCaptureAt: DateTime.now().subtract(const Duration(days: 1)),
    ));

    await tester.pumpWidget(harness());
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('capture-stale-hint')), findsNothing);
  });

  testWidgets('非 Android（isSupported=false）无入口', (tester) async {
    platform.supported = false;
    await tester.pumpWidget(harness());
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('capture-auto-entry-switch')), findsNothing);
    expect(find.textContaining('自动记账'), findsNothing);
  });
}
