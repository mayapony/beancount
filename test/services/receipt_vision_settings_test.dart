import 'package:bean_count/data/db/app_database.dart';
import 'package:bean_count/data/db/connection.dart';
import 'package:bean_count/data/repositories/app_state_repository.dart';
import 'package:bean_count/services/ocr/receipt_vision_settings.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late AppDatabase db;
  late AppStateRepository state;
  late ReceiptVisionSettingsStore store;

  setUp(() async {
    db = AppDatabase(openInMemoryConnection());
    state = AppStateRepository(db);
    store = ReceiptVisionSettingsStore(state);
    await db.select(db.appState).get();
  });

  tearDown(() async => db.close());

  group('默认值', () {
    test('没写过配置时：关闭 + DeepSeek 默认端点', () async {
      final settings = await store.load();
      expect(settings.enabled, isFalse);
      expect(settings.baseUrl, ReceiptVisionSettings.kDefaultBaseUrl);
      expect(settings.model, ReceiptVisionSettings.kDefaultModel);
      expect(settings.isDefaultEndpoint, isTrue);
    });

    test('空字符串与坏值都回落默认', () async {
      await state.write(ReceiptVisionSettingsStore.kBaseUrlKey, '   ');
      await state.write(ReceiptVisionSettingsStore.kModelKey, '');
      await state.write(ReceiptVisionSettingsStore.kEnabledKey, 'not-a-bool');

      final settings = await store.load();
      expect(settings.enabled, isFalse, reason: '非 true 一律当关闭');
      expect(settings.baseUrl, ReceiptVisionSettings.kDefaultBaseUrl);
      expect(settings.model, ReceiptVisionSettings.kDefaultModel);
    });

    test('地址尾部斜杠被归一化', () {
      expect(
        ReceiptVisionSettings.normalizeBaseUrl('https://api.deepseek.com///'),
        'https://api.deepseek.com',
      );
      expect(
        ReceiptVisionSettings.normalizeBaseUrl('  https://example.com/v1 '),
        'https://example.com/v1',
      );
    });
  });

  test('往返：保存后读回来一致', () async {
    const saved = ReceiptVisionSettings(
      enabled: true,
      baseUrl: 'https://example.com/v1/',
      model: 'qwen-vl-max',
    );
    await store.save(saved);

    final loaded = await store.load();
    expect(loaded.enabled, isTrue);
    expect(loaded.baseUrl, 'https://example.com/v1');
    expect(loaded.model, 'qwen-vl-max');
  });

  test('配置只写 app_state，不碰 Key', () async {
    await store.save(const ReceiptVisionSettings(enabled: true));
    final rows = await db.select(db.appState).get();
    expect(
      rows.where((row) => row.key.contains('api')),
      isEmpty,
      reason: 'API Key 不在 app_state',
    );
  });

  group('API Key 存储', () {
    test('内存实现：写入、读取、清除', () async {
      final keys = MemoryReceiptApiKeyStore();
      expect(await keys.read(), isNull);

      await keys.write('  sk-test  ');
      expect(await keys.read(), 'sk-test');

      await keys.clear();
      expect(await keys.read(), isNull);
    });

    test('只写空白视为没有 Key', () async {
      final keys = MemoryReceiptApiKeyStore('   ');
      expect(await keys.read(), isNull);
    });

    test('Key 不落 app_state', () async {
      final keys = MemoryReceiptApiKeyStore();
      await keys.write('sk-secret');
      await store.save(const ReceiptVisionSettings(enabled: true));

      final rows = await db.select(db.appState).get();
      expect(
        rows.any((row) => row.value.contains('sk-secret')),
        isFalse,
        reason: 'Key 只在安全存储里',
      );
    });
  });
}
