import 'dart:convert';

import 'package:bean_count/data/db/app_database.dart';
import 'package:bean_count/data/db/connection.dart';
import 'package:bean_count/data/repositories/app_state_repository.dart';
import 'package:bean_count/services/ocr/auto_create_policy.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late AppDatabase db;
  late AppStateRepository state;
  late DateTime clock;
  late AutoCreatePolicy policy;

  setUp(() async {
    db = AppDatabase(openInMemoryConnection());
    state = AppStateRepository(db);
    clock = DateTime(2026, 10, 18, 12);
    policy = AutoCreatePolicy(state, now: () => clock);
    await db.select(db.appState).get(); // 触发建库
  });

  tearDown(() async => db.close());

  group('分类配额', () {
    test('开关关闭时不建', () async {
      final decision = await policy.checkCategory(enabled: false);
      expect(decision.allowed, isFalse);
      expect(decision.blocked, AutoCreateBlocked.disabled);
    });

    test('单笔最多一个新分类', () async {
      final decision = await policy.checkCategory(enabled: true, requested: 2);
      expect(decision.blocked, AutoCreateBlocked.perEntry);
    });

    test('自动创建累计到 40 个后不建', () async {
      for (var i = 0; i < 40; i++) {
        await policy.markCategoryCreated('cat-auto-$i');
        clock = clock.add(const Duration(minutes: 1));
      }
      expect(
        (await policy.checkCategory(enabled: true)).blocked,
        AutoCreateBlocked.total,
      );
    });

    test('账本里已有 60 多个分类也不拦自动新建', () async {
      // 分类库落库后账本有 65 个分类，但它们都不是自动创建的
      final bookCount = (await db.select(db.categories).get()).length;
      expect(bookCount, greaterThan(60));
      expect((await policy.checkCategory(enabled: true)).allowed, isTrue);
    });

    test('同一个 id 重复记账不重复计数', () async {
      await policy.markCategoryCreated('cat-auto-same');
      await policy.markCategoryCreated('cat-auto-same');
      final raw = await state.read(AutoCreatePolicy.kCategoryIdsKey);
      expect(jsonDecode(raw!) as List, hasLength(1));
    });

    test('7 天内最多三个，滚动窗口外的旧记录不算', () async {
      for (var i = 0; i < 3; i++) {
        await policy.markCategoryCreated('cat-auto-week-$i');
        clock = clock.add(const Duration(hours: 1));
      }
      expect(
        (await policy.checkCategory(enabled: true)).blocked,
        AutoCreateBlocked.weekly,
      );

      final old = [
        for (var i = 0; i < 5; i++)
          clock.subtract(const Duration(days: 8)).toUtc().toIso8601String(),
      ];
      await state.write(AutoCreatePolicy.kCategoryLogKey, jsonEncode(old));
      expect((await policy.checkCategory(enabled: true)).allowed, isTrue);
    });

    test('检查本身不写库', () async {
      await policy.checkCategory(enabled: true);
      expect(await state.read(AutoCreatePolicy.kCategoryLogKey), isNull);
      expect(await state.read(AutoCreatePolicy.kCategoryIdsKey), isNull);
    });
  });

  group('标签配额', () {
    test('单笔最多两个标签', () async {
      expect(
        (await policy.checkTag(enabled: true, requested: 3)).blocked,
        AutoCreateBlocked.perEntry,
      );
      expect(
        (await policy.checkTag(enabled: true, requested: 2)).allowed,
        isTrue,
      );
    });

    test('7 天内最多十个', () async {
      for (var i = 0; i < 10; i++) {
        await policy.markTagCreated();
      }
      expect(
        (await policy.checkTag(enabled: true)).blocked,
        AutoCreateBlocked.weekly,
      );
    });

    test('关闭时不建', () async {
      expect(
        (await policy.checkTag(enabled: false)).blocked,
        AutoCreateBlocked.disabled,
      );
    });
  });

  test('记录时清理过期项', () async {
    final old = [
      clock.subtract(const Duration(days: 30)).toUtc().toIso8601String(),
      clock.subtract(const Duration(days: 1)).toUtc().toIso8601String(),
    ];
    await state.write(AutoCreatePolicy.kCategoryLogKey, jsonEncode(old));

    await policy.markCategoryCreated('cat-auto-new');

    final raw = await state.read(AutoCreatePolicy.kCategoryLogKey);
    final list = jsonDecode(raw!) as List;
    expect(list.length, 2, reason: '保留 1 天前的记录 + 本次新建');
  });

  test('日志损坏时当作没有记录', () async {
    await state.write(AutoCreatePolicy.kTagLogKey, 'not json');
    expect((await policy.checkTag(enabled: true)).allowed, isTrue);
  });
}
