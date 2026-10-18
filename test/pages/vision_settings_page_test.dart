import 'package:bean_count/data/db/app_database.dart';
import 'package:bean_count/data/db/connection.dart';
import 'package:bean_count/data/repositories/app_state_repository.dart';
import 'package:bean_count/pages/vision_settings_page.dart';
import 'package:bean_count/services/ocr/receipt_vision_settings.dart';
import 'package:bean_count/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late AppDatabase db;
  late ReceiptVisionSettingsStore settings;
  late MemoryReceiptApiKeyStore keys;

  setUp(() async {
    db = AppDatabase(openInMemoryConnection());
    settings = ReceiptVisionSettingsStore(AppStateRepository(db));
    keys = MemoryReceiptApiKeyStore();
    await db.select(db.appState).get();
  });

  tearDown(() async => db.close());

  Future<void> pump(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: buildBeanTheme(Brightness.light),
        home: VisionSettingsPage(settings: settings, keys: keys),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> toggle(WidgetTester tester) async {
    await tester.tap(find.byKey(const ValueKey('vision-switch')));
    await tester.pumpAndSettle();
  }

  /// 页面比 600px 高的测试窗口长：先滚到按钮再点，否则点击落在屏幕外。
  Future<void> tapKey(WidgetTester tester, String key) async {
    final finder = find.byKey(ValueKey(key));
    await tester.ensureVisible(finder);
    await tester.pumpAndSettle();
    await tester.tap(finder);
    await tester.pumpAndSettle();
  }

  Future<void> enterKey(WidgetTester tester, String value) async {
    await tester.enterText(
      find.byKey(const ValueKey('vision-key-field')),
      value,
    );
    await tapKey(tester, 'vision-key-save');
  }

  testWidgets('默认关闭，并承诺图片不离开设备', (tester) async {
    await pump(tester);

    expect(find.text('关闭时不做识别，图片不会离开设备'), findsOneWidget);
    final switchTile = tester.widget<SwitchListTile>(
      find.byKey(const ValueKey('vision-switch')),
    );
    expect(switchTile.value, isFalse);
    expect(find.byKey(const ValueKey('vision-key-clear')), findsNothing);
  });

  testWidgets('默认显示 DeepSeek 地址与模型', (tester) async {
    await pump(tester);

    expect(
      find.text(ReceiptVisionSettings.kDefaultBaseUrl),
      findsOneWidget,
    );
    expect(find.text(ReceiptVisionSettings.kDefaultModel), findsOneWidget);
  });

  testWidgets('开启但没 Key：提示不生效，配置仍是开启', (tester) async {
    await pump(tester);
    await toggle(tester);

    expect(find.textContaining('已开启但还没有 API Key'), findsOneWidget);
    expect((await settings.load()).enabled, isTrue);
  });

  testWidgets('保存 Key 后生效，Key 不回显', (tester) async {
    await pump(tester);
    await toggle(tester);
    await enterKey(tester, 'sk-secret');

    expect(await keys.read(), 'sk-secret');
    expect(find.text('sk-secret'), findsNothing, reason: 'Key 不回显');
    expect(find.byKey(const ValueKey('vision-key-clear')), findsOneWidget);
    expect(find.textContaining('识别已生效'), findsOneWidget);
  });

  testWidgets('清除 Key 会自动关闭识别', (tester) async {
    await pump(tester);
    await toggle(tester);
    await enterKey(tester, 'sk-secret');
    expect((await settings.load()).enabled, isTrue);

    await tapKey(tester, 'vision-key-clear');

    expect(await keys.read(), isNull);
    expect((await settings.load()).enabled, isFalse);
    expect(find.textContaining('已清除 API Key'), findsOneWidget);
  });

  testWidgets('高级：改地址与模型后保存，可恢复默认', (tester) async {
    await pump(tester);

    await tester.enterText(
      find.byKey(const ValueKey('vision-base-url')),
      'https://example.com/v1/',
    );
    await tester.enterText(
      find.byKey(const ValueKey('vision-model')),
      'qwen-vl-max',
    );
    await tapKey(tester, 'vision-advanced-save');

    var saved = await settings.load();
    expect(saved.baseUrl, 'https://example.com/v1');
    expect(saved.model, 'qwen-vl-max');

    await tapKey(tester, 'vision-advanced-reset');

    saved = await settings.load();
    expect(saved.baseUrl, ReceiptVisionSettings.kDefaultBaseUrl);
    expect(saved.model, ReceiptVisionSettings.kDefaultModel);
  });

  testWidgets('空地址与空模型保存为默认值', (tester) async {
    await pump(tester);

    await tester.enterText(find.byKey(const ValueKey('vision-base-url')), '   ');
    await tester.enterText(find.byKey(const ValueKey('vision-model')), '');
    await tapKey(tester, 'vision-advanced-save');

    final saved = await settings.load();
    expect(saved.baseUrl, ReceiptVisionSettings.kDefaultBaseUrl);
    expect(saved.model, ReceiptVisionSettings.kDefaultModel);
  });
}
