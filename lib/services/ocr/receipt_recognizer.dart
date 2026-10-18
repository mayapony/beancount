import 'dart:typed_data';

import 'receipt_guess.dart';

/// 小票识别器：图片 → 结构化的一笔账。
///
/// 抽象出来的原因：
/// - 识别失败可以无声降级（返回空结果），不影响手动记账；
/// - 没配置视觉模型（Web/未开启/无 Key）时用空实现即可。
abstract class ReceiptRecognizer {
  /// 识别一张图；认不出任何字段时返回 [ReceiptGuess.empty]。
  Future<ReceiptGuess> recognize(Uint8List bytes);

  Future<void> close();
}

/// 不识别（Web/桌面/测试）。
class NoopReceiptRecognizer implements ReceiptRecognizer {
  @override
  Future<ReceiptGuess> recognize(Uint8List bytes) async => ReceiptGuess.empty;

  @override
  Future<void> close() async {}
}
