import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kIsWeb, TargetPlatform;

import 'receipt_recognizer.dart';
import 'receipt_recognizer_mlkit.dart';

/// 当前平台可用的识别器；不能识别时返回 null（面板据此不显示识别能力）。
///
/// 只在 Android/iOS 启用：ML Kit 的中文模型随 APK 打包，其它平台没有。
ReceiptRecognizer? systemReceiptRecognizer() {
  if (kIsWeb) return null;
  if (defaultTargetPlatform == TargetPlatform.android ||
      defaultTargetPlatform == TargetPlatform.iOS) {
    return MlKitReceiptRecognizer();
  }
  return null;
}
