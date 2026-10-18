import 'package:bean_count/data/db/app_database.dart';
import 'package:bean_count/data/db/connection.dart';
import 'package:bean_count/data/repositories/app_state_repository.dart';
import 'package:bean_count/pages/vision_settings_page.dart';
import 'package:bean_count/services/ocr/receipt_guess.dart';
import 'package:bean_count/services/ocr/receipt_vision_settings.dart';
import 'package:bean_count/services/ocr/vision_probe.dart';
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

  Future<void> pump(WidgetTester tester, {VisionProbeRunner? probe}) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: buildBeanTheme(Brightness.light),
        home: VisionSettingsPage(settings: settings, keys: keys, probe: probe),
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
    await tapKey(tester, 'vision-save');
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
    await tapKey(tester, 'vision-save');

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
    await tapKey(tester, 'vision-save');

    final saved = await settings.load();
    expect(saved.baseUrl, ReceiptVisionSettings.kDefaultBaseUrl);
    expect(saved.model, ReceiptVisionSettings.kDefaultModel);
  });

  testWidgets('一次保存同时写入 Key 与高级设置', (tester) async {    await pump(tester);
    await toggle(tester);

    await tester.enterText(
      find.byKey(const ValueKey('vision-key-field')),
      'sk-secret',
    );
    await tester.enterText(
      find.byKey(const ValueKey('vision-base-url')),
      'https://example.com/v1',
    );
    await tester.enterText(
      find.byKey(const ValueKey('vision-model')),
      'qwen-vl-max',
    );
    await tapKey(tester, 'vision-save');

    expect(await keys.read(), 'sk-secret');
    final saved = await settings.load();
    expect(saved.baseUrl, 'https://example.com/v1');
    expect(saved.model, 'qwen-vl-max');
    expect(saved.enabled, isTrue);
  });

  group('测试识别', () {
    testWidgets('用表单里刚填的 Key 测试，不先落库', (tester) async {
      var calls = 0;
      String? usedKey;
      String? usedBaseUrl;
      String? usedModel;
      await pump(
        tester,
        probe: ({required baseUrl, required model, required apiKey}) async {
          calls++;
          usedKey = apiKey;
          usedBaseUrl = baseUrl;
          usedModel = model;
          return const VisionProbeResult.success(
            ReceiptGuess(amountCents: 1234),
          );
        },
      );

      await tester.enterText(
        find.byKey(const ValueKey('vision-base-url')),
        'https://example.com/v1/',
      );
      await tester.enterText(
        find.byKey(const ValueKey('vision-model')),
        'qwen-vl-max',
      );
      await tester.enterText(
        find.byKey(const ValueKey('vision-key-field')),
        'sk-typed',
      );
      await tapKey(tester, 'vision-probe');

      expect(calls, 1);
      expect(usedKey, 'sk-typed');
      expect(usedBaseUrl, 'https://example.com/v1');
      expect(usedModel, 'qwen-vl-max');
      expect(await keys.read(), isNull, reason: '测试不保存 Key');
      expect(
        find.text('识别正常：测试小票 ¥12.34'),
        findsOneWidget,
      );
    });

    testWidgets('已保存的 Key 也能直接测', (tester) async {
      await keys.write('sk-saved');
      String? usedKey;
      await pump(
        tester,
        probe: ({required baseUrl, required model, required apiKey}) async {
          usedKey = apiKey;
          return const VisionProbeResult.success(
            ReceiptGuess(amountCents: 1234),
          );
        },
      );

      await tapKey(tester, 'vision-probe');
      expect(usedKey, 'sk-saved');
    });

    testWidgets('失败时把原因写在页面上', (tester) async {
      await pump(
        tester,
        probe: ({required baseUrl, required model, required apiKey}) async =>
            const VisionProbeResult.failure('API Key 无效或没有权限'),
      );

      await tester.enterText(
        find.byKey(const ValueKey('vision-key-field')),
        'sk-wrong',
      );
      await tapKey(tester, 'vision-probe');

      expect(
        find.text('测试失败：API Key 无效或没有权限'),
        findsOneWidget,
      );
    });

    testWidgets('没填也没存的 Key：不调用测试，先提示', (tester) async {
      var calls = 0;
      await pump(
        tester,
        probe: ({required baseUrl, required model, required apiKey}) async {
          calls++;
          return const VisionProbeResult.success(
            ReceiptGuess(amountCents: 1234),
          );
        },
      );

      await tapKey(tester, 'vision-probe');

      expect(calls, 0);
      expect(find.text('先填一个 API Key 再测试'), findsOneWidget);
    });
  });
}
