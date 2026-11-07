library;

import 'dart:convert';

import '../../data/repositories/app_state_repository.dart';

/// 「包名 + 渠道词 → 账户」的记忆。
///
/// 同一个 App 的付款渠道通常稳定，所以用户为它选过一次账户之后，后续同一组合
/// 就该直接套用，而不是每笔都问一遍。键是 `包名|渠道词`（渠道词小写、去空格），
/// 没有渠道词时用 `包名|`，与「支付宝用余额宝」和「京东用银行卡」互不干扰。
class CaptureAccountMap {
  CaptureAccountMap(this._state);

  final AppStateRepository _state;

  static const kKey = 'capture_account_map';

  Future<String?> lookup(String packageName, String? channel) async {
    final map = await _load();
    return map[_keyOf(packageName, channel)];
  }

  /// 记住一次用户的选择；账户为空时不做任何事。
  Future<void> remember(
    String packageName,
    String? channel,
    String accountId,
  ) async {
    if (packageName.isEmpty || accountId.isEmpty) return;
    final map = await _load();
    map[_keyOf(packageName, channel)] = accountId;
    await _state.write(kKey, jsonEncode(map));
  }

  Future<void> forget(String packageName, String? channel) async {
    final map = await _load();
    if (map.remove(_keyOf(packageName, channel)) == null) return;
    await _state.write(kKey, jsonEncode(map));
  }

  static String _keyOf(String packageName, String? channel) =>
      '$packageName|${(channel ?? '').trim().toLowerCase()}';

  Future<Map<String, String>> _load() async {
    final raw = await _state.read(kKey);
    if (raw == null || raw.trim().isEmpty) return <String, String>{};
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return <String, String>{};
      return {
        for (final entry in decoded.entries)
          entry.key.toString(): entry.value.toString(),
      };
    } on FormatException {
      return <String, String>{};
    }
  }
}
