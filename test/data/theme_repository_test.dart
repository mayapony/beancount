import 'package:bean_count/data/db/app_database.dart';
import 'package:drift/drift.dart' show InsertMode;
import 'package:bean_count/data/db/connection.dart';
import 'package:bean_count/data/repositories/theme_repository.dart';
import 'package:bean_count/theme/theme_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ThemeRepository', () {
    late AppDatabase db;
    late ThemeRepository repo;

    setUp(() async {
      db = AppDatabase(openInMemoryConnection());
      repo = ThemeRepository(db);
      await db.select(db.appState).get();
    });

    tearDown(() async => db.close());

    test('默认跟随系统', () async {
      expect(await repo.load(), ThemeMode.system);
    });

    test('写入后可读回', () async {
      await repo.save(ThemeMode.dark);
      expect(await repo.load(), ThemeMode.dark);

      await repo.save(ThemeMode.light);
      expect(await repo.load(), ThemeMode.light);
    });

    test('非法值回落跟随系统', () async {
      await db.into(db.appState).insert(
            AppStateCompanion.insert(key: ThemeRepository.key, value: 'purple'),
            mode: InsertMode.insertOrReplace,
          );
      expect(await repo.load(), ThemeMode.system);
    });

    test('三档的中文名', () {
      expect(ThemeRepository.labelOf(ThemeMode.system), '跟随系统');
      expect(ThemeRepository.labelOf(ThemeMode.light), '浅色');
      expect(ThemeRepository.labelOf(ThemeMode.dark), '深色');
    });
  });

  group('ThemeController', () {
    late AppDatabase db;
    late ThemeController controller;

    setUp(() async {
      db = AppDatabase(openInMemoryConnection());
      await db.select(db.appState).get();
      controller = ThemeController(repository: ThemeRepository(db));
    });

    tearDown(() async => db.close());

    test('set 之后 mode 变且通知一次，并落库', () async {
      var notified = 0;
      controller.addListener(() => notified++);

      await controller.setThemeMode(ThemeMode.dark);
      expect(controller.mode, ThemeMode.dark);
      expect(controller.label, '深色');
      expect(notified, 1);

      // 读回来确认落库了
      expect(await ThemeRepository(db).load(), ThemeMode.dark);

      // 同样的值不重复通知
      await controller.setThemeMode(ThemeMode.dark);
      expect(notified, 1);
    });

    test('load 读到已保存的值', () async {
      await ThemeRepository(db).save(ThemeMode.light);
      await controller.load();
      expect(controller.mode, ThemeMode.light);
    });

    test('没有保存过时 load 保持跟随系统', () async {
      await controller.load();
      expect(controller.mode, ThemeMode.system);
    });
  });
}
