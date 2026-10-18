import 'dart:convert';

import '../../data/repositories/app_state_repository.dart';
import '../ocr/receipt_guess.dart';

/// 后台识别完成、等着用户打开面板的那一笔。
///
/// 落在 `app_state` 的 `pending_screenshot_entries`（JSON 列表，最多
/// [PendingScreenshotEntryStore.kMaxEntries] 条）：后台引擎追加，主界面
/// 逐条消费。识别失败也写一条（带 [error]），这样用户至少知道
/// 「刚才那张截图没识别出来」，而不是石沉大海。
class PendingScreenshotEntry {
  const PendingScreenshotEntry({
    required this.id,
    required this.createdAt,
    this.guess,
    this.imagePath,
    this.error,
  });

  final String id;
  final DateTime createdAt;

  /// 识别结果；识别失败时为空。
  final ReceiptGuess? guess;

  /// 截图文件的临时路径（存在时随面板一起作为附件）。
  final String? imagePath;

  /// 识别失败原因（可读文案）；成功时为空。
  final String? error;

  Map<String, dynamic> toJson() => {
        'id': id,
        'created_at': createdAt.toUtc().toIso8601String(),
        if (guess != null) ..._guessToJson(guess!),
        if (imagePath != null) 'image_path': imagePath,
        if (error != null) 'error': error,
      };

  static PendingScreenshotEntry? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final id = raw['id'];
    final createdAt = DateTime.tryParse(raw['created_at']?.toString() ?? '');
    if (id is! String || createdAt == null) return null;

    final amount = raw['amount_cents'];
    final happenedAt = DateTime.tryParse(raw['happened_at']?.toString() ?? '');
    final tags = raw['tag_names'];
    final confidence = ReceiptConfidence.values
        .where((value) => value.name == raw['confidence'])
        .firstOrNull;

    final guess = ReceiptGuess(
      amountCents: amount is int ? amount : null,
      categoryName: raw['category_name']?.toString(),
      tagNames: tags is List
          ? tags.whereType<String>().toList(growable: false)
          : const [],
      accountName: raw['account_name']?.toString(),
      note: raw['note']?.toString(),
      happenedAt: happenedAt,
      confidence: confidence ?? ReceiptConfidence.none,
    );

    return PendingScreenshotEntry(
      id: id,
      createdAt: createdAt,
      guess: guess.isEmpty && amount == null ? null : guess,
      imagePath: raw['image_path']?.toString(),
      error: raw['error']?.toString(),
    );
  }

  static Map<String, dynamic> _guessToJson(ReceiptGuess guess) => {
        if (guess.amountCents != null) 'amount_cents': guess.amountCents,
        if (guess.categoryName != null) 'category_name': guess.categoryName,
        if (guess.tagNames.isNotEmpty) 'tag_names': guess.tagNames,
        if (guess.accountName != null) 'account_name': guess.accountName,
        if (guess.note != null) 'note': guess.note,
        if (guess.happenedAt != null)
          'happened_at': guess.happenedAt!.toUtc().toIso8601String(),
        'confidence': guess.confidence.name,
      };
}

/// 待处理识别的读写。
///
/// 每条 pending 用独立的 `app_state` key（`pending_screenshot:<id>`），而不是
/// 一个 JSON 列表：主界面引擎和后台识别引擎可能同时 add/take，独立 key 的
/// 写入和删除是原子的，不会出现「你读我写」把对方那条覆盖掉。
///
/// 连续截图按 `createdAt` 排队；`take` 取最早的一条并删除，最多保留
/// [kMaxEntries] 条。
class PendingScreenshotEntryStore {
  PendingScreenshotEntryStore(this._state);

  final AppStateRepository _state;
  bool _legacyChecked = false;

  static const kKeyPrefix = 'pending_screenshot:';
  static const kLegacyKey = 'pending_screenshot_entry';
  static const kLegacyListKey = 'pending_screenshot_entries';
  static const kMaxEntries = 10;

  /// 兼容旧调用：写入即追加（同 id 覆盖）。
  Future<void> write(PendingScreenshotEntry entry) async {
    await add(entry);
  }

  /// 追加一条并返回队列长度；超过上限时丢最老的。
  Future<int> add(PendingScreenshotEntry entry) async {
    await _state.write(_keyOf(entry.id), jsonEncode(entry.toJson()));
    await _prune();
    return count();
  }

  Future<List<PendingScreenshotEntry>> readAll() async {
    final stored = await _readStored();
    return [for (final item in stored) item.entry];
  }

  Future<PendingScreenshotEntry?> peek() async {
    final stored = await _readStored();
    return stored.isEmpty ? null : stored.first.entry;
  }

  Future<int> count() async => (await _readStored()).length;

  /// 取最早的一条并删除；没有待处理项时返回 null。
  ///
  /// 两个引擎可能同时消费：只有真正删到 key 的那一方拿走，删不到就重读下一条。
  Future<PendingScreenshotEntry?> take() async {
    for (var attempt = 0; attempt < 3; attempt++) {
      final stored = await _readStored();
      if (stored.isEmpty) return null;
      final first = stored.first;
      if (await _state.removeIfPresent(first.key)) return first.entry;
    }
    return null;
  }

  Future<void> clear() async {
    final stored = await _readStored();
    for (final item in stored) {
      await _state.removeIfPresent(item.key);
    }
    await _state.remove(kLegacyKey);
    await _state.remove(kLegacyListKey);
  }

  Future<List<_StoredEntry>> _readStored() async {
    await _migrateLegacy();
    final rows = await _state.readStartingWith(kKeyPrefix);
    final stored = <_StoredEntry>[];
    for (final row in rows) {
      final entry = _decodeEntry(row.value);
      if (entry != null) stored.add(_StoredEntry(row.key, entry));
    }
    stored.sort((a, b) {
      final byTime = a.entry.createdAt.compareTo(b.entry.createdAt);
      return byTime != 0 ? byTime : a.entry.id.compareTo(b.entry.id);
    });
    return stored;
  }

  Future<void> _prune() async {
    final stored = await _readStored();
    if (stored.length <= kMaxEntries) return;
    for (final item in stored.take(stored.length - kMaxEntries)) {
      await _state.removeIfPresent(item.key);
    }
  }

  /// 旧版本的单条 key / 中间版本的单 key 列表，首次读取时迁到独立 key。
  /// 两个引擎同时迁移也安全：写入按 id 幂等，删除谁先删到算谁。
  Future<void> _migrateLegacy() async {
    if (_legacyChecked) return;

    final legacy = _decodeEntry(await _state.read(kLegacyKey));
    if (legacy != null) {
      await _state.write(_keyOf(legacy.id), jsonEncode(legacy.toJson()));
    }
    await _state.removeIfPresent(kLegacyKey);

    final legacyList = await _state.read(kLegacyListKey);
    if (legacyList != null) {
      for (final entry in _decodeList(legacyList)) {
        await _state.write(_keyOf(entry.id), jsonEncode(entry.toJson()));
      }
      await _state.removeIfPresent(kLegacyListKey);
    }
    _legacyChecked = true;
  }

  static String _keyOf(String id) => '$kKeyPrefix$id';

  static List<PendingScreenshotEntry> _decodeList(String? raw) {
    if (raw == null || raw.trim().isEmpty) return [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return [];
      final entries = <PendingScreenshotEntry>[];
      for (final item in decoded) {
        final entry = PendingScreenshotEntry.fromJson(item);
        if (entry != null) entries.add(entry);
      }
      return entries;
    } on FormatException {
      // 坏数据不该把用户卡在启动流程里
      return [];
    }
  }

  static PendingScreenshotEntry? _decodeEntry(String? raw) {
    if (raw == null || raw.trim().isEmpty) return null;
    try {
      return PendingScreenshotEntry.fromJson(jsonDecode(raw));
    } on FormatException {
      return null;
    }
  }
}

class _StoredEntry {
  const _StoredEntry(this.key, this.entry);

  final String key;
  final PendingScreenshotEntry entry;
}
