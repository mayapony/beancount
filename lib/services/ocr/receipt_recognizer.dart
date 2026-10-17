import 'dart:typed_data';

import 'receipt_parser.dart';

/// 小票识别器：只负责"图 → 文字"，理解交给 [parseReceiptText]。
///
/// 抽象出来的原因：
/// - 解析器可以在没有设备的单元测试里跑；
/// - Web/桌面没有 ML Kit，用空实现即可，不影响记账。
abstract class ReceiptRecognizer {
  /// 返回识别出的整段文字；没有文字时返回 null。
  Future<String?> recognizeText(Uint8List bytes);

  Future<void> close();
}

/// 不识别（Web/桌面/测试）。
class NoopReceiptRecognizer implements ReceiptRecognizer {
  @override
  Future<String?> recognizeText(Uint8List bytes) async => null;

  @override
  Future<void> close() async {}
}

/// 把文字解析成 [`ReceiptGuess`]；识别失败返回空。
Future<ReceiptGuess> recognizeReceipt(
  ReceiptRecognizer recognizer,
  Uint8List bytes, {
  DateTime? now,
}) async {
  final text = await recognizer.recognizeText(bytes);
  if (text == null || text.trim().isEmpty) return ReceiptGuess.empty;
  return parseReceiptText(text, now: now);
}
