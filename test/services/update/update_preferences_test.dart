import 'package:flutter_test/flutter_test.dart';

import 'package:bean_count/data/db/app_database.dart';
import 'package:bean_count/data/db/connection.dart';
import 'package:bean_count/data/repositories/app_state_repository.dart';
import 'package:bean_count/services/update/update_preferences.dart';

void main() {
  late AppDatabase db;
  late UpdatePreferences prefs;

  final now = DateTime.utc(2026, 10, 18, 12);

  setUp(() async {
    db = AppDatabase(openInMemoryConnection());
    prefs = UpdatePreferences(AppStateRepository(db));
    await db.select(db.appState).get();
  });

  tearDown(() async => db.close());

  test('默认开启自动检查，且从未检查时判定为到点', () async {
    expect(await prefs.autoCheckEnabled(), isTrue);
    expect(await prefs.lastCheckedAt(), isNull);
    expect(await prefs.shouldAutoCheck(now), isTrue);
  });

  test('关闭自动检查后不再到点', () async {
    await prefs.setAutoCheckEnabled(false);

    expect(await prefs.autoCheckEnabled(), isFalse);
    expect(await prefs.shouldAutoCheck(now), isFalse);
  });

  test('24 小时内不重复检查，超过 24 小时恢复', () async {
    await prefs.markChecked(now);

    expect(
      await prefs.shouldAutoCheck(now.add(const Duration(hours: 12))),
      isFalse,
    );
    expect(
      await prefs.shouldAutoCheck(now.add(const Duration(hours: 24))),
      isTrue,
    );
  });

  test('ETag 可写入、可清除', () async {
    await prefs.setEtag('W/"abc"');
    expect(await prefs.etag(), 'W/"abc"');

    await prefs.setEtag(null);
    expect(await prefs.etag(), isNull);
  });

  test('跳过的版本不再自动提示，但其他版本仍提示', () async {
    await prefs.skipVersion('1.0.2');

    expect(await prefs.shouldPrompt('1.0.2', now), isFalse);
    expect(await prefs.shouldPrompt('1.0.3', now), isTrue);
  });

  test('同一版本「以后再说」24 小时内不提示，之后恢复', () async {
    await prefs.dismiss('1.0.2', now);

    expect(
      await prefs.shouldPrompt('1.0.2', now.add(const Duration(hours: 2))),
      isFalse,
    );
    expect(
      await prefs.shouldPrompt('1.0.2', now.add(const Duration(hours: 24))),
      isTrue,
    );
    expect(await prefs.shouldPrompt('1.0.3', now), isTrue);
  });

  test('待安装版本可写入与清除', () async {
    await prefs.setPendingVersion('1.0.2');
    expect(await prefs.pendingVersion(), '1.0.2');

    await prefs.setPendingVersion(null);
    expect(await prefs.pendingVersion(), isNull);
  });
}
