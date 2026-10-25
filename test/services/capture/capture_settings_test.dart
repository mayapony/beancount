import 'package:bean_count/data/db/app_database.dart';
import 'package:bean_count/data/db/connection.dart';
import 'package:bean_count/data/repositories/app_state_repository.dart';
import 'package:bean_count/services/capture/capture_settings.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late AppDatabase db;
  late CaptureSettingsStore store;

  setUp(() async {
    db = AppDatabase(openInMemoryConnection());
    store = CaptureSettingsStore(AppStateRepository(db));
    await db.select(db.appState).get(); // 建库
  });

  tearDown(() async => db.close());

  test('默认关闭', () async {
    final settings = await store.load();
    expect(settings.enabled, isFalse);
    expect(settings.lastCaptureAt, isNull);
  });

  test('开启与心跳持久化', () async {
    await store.setEnabled(true);
    await store.markCaptured(DateTime.utc(2026, 10, 18, 12));

    final settings = await store.load();
    expect(settings.enabled, isTrue);
    expect(settings.lastCaptureAt, DateTime.utc(2026, 10, 18, 12));
  });

  test('未开启不判失效', () {
    expect(
      isCaptureStale(
        enabled: false,
        lastCaptureAt: DateTime.now().subtract(const Duration(days: 30)),
        now: DateTime.now(),
      ),
      isFalse,
    );
  });

  test('从未捕获不判失效', () {
    expect(
      isCaptureStale(enabled: true, lastCaptureAt: null, now: DateTime.now()),
      isFalse,
    );
  });

  test('超过 7 天零捕获判失效', () {
    final now = DateTime(2026, 10, 25, 9, 0);
    expect(
      isCaptureStale(
        enabled: true,
        lastCaptureAt: now.subtract(const Duration(days: 7, minutes: 1)),
        now: now,
      ),
      isTrue,
    );
  });

  test('恢复捕获后失效消失', () {
    final now = DateTime(2026, 10, 25, 9, 0);
    expect(
      isCaptureStale(
        enabled: true,
        lastCaptureAt: now.subtract(const Duration(days: 1)),
        now: now,
      ),
      isFalse,
    );
  });
}
