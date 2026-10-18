import 'package:bean_count/data/db/app_database.dart';
import 'package:bean_count/data/db/connection.dart';
import 'package:bean_count/data/repositories/app_state_repository.dart';
import 'package:bean_count/services/ocr/receipt_recognizer.dart';
import 'package:bean_count/services/ocr/receipt_recognizer_factory.dart';
import 'package:bean_count/services/ocr/receipt_recognizer_vision.dart';
import 'package:bean_count/services/ocr/receipt_vision_settings.dart';
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

  Future<ReceiptRecognizer?> build() => systemReceiptRecognizer(
        settings: settings,
        keys: keys,
      );

  test('默认关闭：没有识别器', () async {
    expect(await build(), isNull);
  });

  test('只有开关没有 Key：不生效', () async {
    await settings.save(const ReceiptVisionSettings(enabled: true));
    expect(await build(), isNull);
  });

  test('只有 Key 没开开关：不生效（图片不出设备）', () async {
    await keys.write('sk-test');
    expect(await build(), isNull);
  });

  test('开启且已存 Key：得到视觉识别器', () async {
    await settings.save(const ReceiptVisionSettings(enabled: true));
    await keys.write('sk-test');

    final recognizer = await build();
    expect(recognizer, isA<VisionReceiptRecognizer>());
    await recognizer!.close();
  });

  test('关掉开关后立即不再识别', () async {
    await settings.save(const ReceiptVisionSettings(enabled: true));
    await keys.write('sk-test');
    await (await build())?.close();

    await settings.save(const ReceiptVisionSettings(enabled: false));
    expect(await build(), isNull);
  });

  test('清掉 Key 后立即不再识别', () async {
    await settings.save(const ReceiptVisionSettings(enabled: true));
    await keys.write('sk-test');
    await (await build())?.close();

    await keys.clear();
    expect(await build(), isNull);
  });
}
