import 'dart:convert';

import '../../data/repositories/app_state_repository.dart';
import '../ocr/receipt_guess.dart';

/// 后台识别完成、等着用户打开面板的那一笔。
///
/// 落在一个 `app_state` 键里（`pending_screenshot_entry`）：后台引擎写，
/// 主界面读一次就清掉。识别失败也写一条（带 [error]），这样用户至少知道
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

/// 待处理识别的读写。`take` 是「读一次并清掉」，避免重复弹面板。
class PendingScreenshotEntryStore {
  PendingScreenshotEntryStore(this._state);

  final AppStateRepository _state;

  static const kKey = 'pending_screenshot_entry';

  Future<void> write(PendingScreenshotEntry entry) =>
      _state.write(kKey, jsonEncode(entry.toJson()));

  Future<PendingScreenshotEntry?> peek() async {
    final raw = await _state.read(kKey);
    if (raw == null || raw.trim().isEmpty) return null;
    try {
      return PendingScreenshotEntry.fromJson(jsonDecode(raw));
    } on FormatException {
      // 坏数据不该把用户卡在启动流程里
      return null;
    }
  }

  /// 读并清空；没有待处理项时返回 null。
  Future<PendingScreenshotEntry?> take() async {
    final entry = await peek();
    if (entry != null) await clear();
    return entry;
  }

  Future<void> clear() => _state.remove(kKey);
}
