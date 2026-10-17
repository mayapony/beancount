import 'package:drift/drift.dart';

import '../db/app_database.dart';
import '../../services/security/pin_hasher.dart';

/// 应用锁的存储：只存盐与摘要，不存明文 PIN。
///
/// 键都在 `app_state` 里，所以不需要新的数据库迁移。
class LockRepository {
  LockRepository(this._db);

  final AppDatabase _db;

  static const _kEnabled = 'lock_enabled';
  static const _kSalt = 'lock_pin_salt';
  static const _kDigest = 'lock_pin_digest';
  static const _kLength = 'lock_pin_length';

  Future<String?> _read(String key) async {
    final row = await (_db.select(_db.appState)
          ..where((t) => t.key.equals(key)))
        .getSingleOrNull();
    return row?.value;
  }

  Future<void> _write(String key, String value) async {
    await _db.into(_db.appState).insert(
          AppStateCompanion.insert(key: key, value: value),
          mode: InsertMode.insertOrReplace,
        );
  }

  Future<void> _delete(String key) async {
    await (_db.delete(_db.appState)..where((t) => t.key.equals(key))).go();
  }

  /// 是否开启应用锁。读不到/解析失败一律按"未开启"处理——
  /// 不能因为存储异常把用户锁在自己门外。
  Future<bool> isEnabled() async {
    try {
      return await _read(_kEnabled) == 'true';
    } catch (_) {
      return false;
    }
  }

  /// PIN 位数（界面画圆点用）；没有记录时回到 6。
  Future<int> pinLength() async {
    final raw = await _read(_kLength);
    final value = int.tryParse(raw ?? '');
    if (value == null || value < kPinMinLength || value > kPinMaxLength) {
      return kPinMaxLength;
    }
    return value;
  }

  /// 设置（或修改）PIN 并开启应用锁。
  Future<void> setPin(String pin) async {
    final digest = digestPin(pin);
    await _write(_kSalt, digest.salt);
    await _write(_kDigest, digest.digest);
    await _write(_kLength, '${digest.length}');
    await _write(_kEnabled, 'true');
  }

  /// 校验 PIN；没有设置过或未开启时恒为 false。
  Future<bool> verify(String pin) async {
    final salt = await _read(_kSalt);
    final digest = await _read(_kDigest);
    if (salt == null || digest == null) return false;
    return verifyPin(pin: pin, salt: salt, digest: digest);
  }

  /// 关闭应用锁并清掉 PIN 记录。
  Future<void> disable() async {
    await _delete(_kEnabled);
    await _delete(_kSalt);
    await _delete(_kDigest);
    await _delete(_kLength);
  }
}
