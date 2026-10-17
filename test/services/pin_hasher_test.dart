import 'dart:math';

import 'package:bean_count/data/db/app_database.dart';
import 'package:bean_count/data/db/connection.dart';
import 'package:bean_count/data/repositories/lock_repository.dart';
import 'package:bean_count/services/security/pin_hasher.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('PIN 摘要', () {
    test('同一 PIN、不同盐得到不同摘要', () {
      final a = digestPin('1234', random: Random(1));
      final b = digestPin('1234', random: Random(2));
      expect(a.salt, isNot(b.salt));
      expect(a.digest, isNot(b.digest));
      expect(a.length, 4);
    });

    test('正确 PIN 校验通过，错误 PIN 不通过', () {
      final digest = digestPin('2468', random: Random(3));
      expect(
        verifyPin(pin: '2468', salt: digest.salt, digest: digest.digest),
        isTrue,
      );
      expect(
        verifyPin(pin: '2469', salt: digest.salt, digest: digest.digest),
        isFalse,
      );
      expect(
        verifyPin(pin: '', salt: digest.salt, digest: digest.digest),
        isFalse,
      );
    });

    test('PIN 长度与字符校验', () {
      expect(isValidPin('1234'), isTrue);
      expect(isValidPin('123456'), isTrue);
      expect(isValidPin('123'), isFalse);
      expect(isValidPin('1234567'), isFalse);
      expect(isValidPin('12a4'), isFalse);
      expect(() => digestPin('12'), throwsA(isA<ArgumentError>()));
    });

    test('摘要里不含明文 PIN', () {
      final digest = digestPin('2468', random: Random(4));
      expect(digest.salt.contains('2468'), isFalse);
      expect(digest.digest.contains('2468'), isFalse);
    });
  });

  group('LockRepository', () {
    late AppDatabase db;
    late LockRepository lock;

    setUp(() async {
      db = AppDatabase(openInMemoryConnection());
      lock = LockRepository(db);
      await db.select(db.appState).get();
    });

    tearDown(() async => db.close());

    test('默认未开启', () async {
      expect(await lock.isEnabled(), isFalse);
      expect(await lock.verify('1234'), isFalse);
    });

    test('设置 PIN 后可校验，且库里没有明文', () async {
      await lock.setPin('1234');
      expect(await lock.isEnabled(), isTrue);
      expect(await lock.pinLength(), 4);
      expect(await lock.verify('1234'), isTrue);
      expect(await lock.verify('4321'), isFalse);

      final rows = await db.select(db.appState).get();
      expect(
        rows.any((r) => r.value.contains('1234')),
        isFalse,
        reason: 'app_state 里不能存明文 PIN',
      );
    });

    test('关闭后清掉全部记录', () async {
      await lock.setPin('2468');
      await lock.disable();

      expect(await lock.isEnabled(), isFalse);
      expect(await lock.verify('2468'), isFalse);
      final rows = await db.select(db.appState).get();
      expect(
        rows.where((r) => r.key.startsWith('lock_')),
        isEmpty,
      );
    });

    test('改 PIN 后旧 PIN 失效', () async {
      await lock.setPin('1234');
      await lock.setPin('5678');
      expect(await lock.verify('1234'), isFalse);
      expect(await lock.verify('5678'), isTrue);
    });
  });
}
