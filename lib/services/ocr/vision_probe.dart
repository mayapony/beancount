import 'dart:typed_data';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:http/http.dart' as http;

import 'probe_receipt_image.dart';
import 'receipt_guess.dart';
import 'receipt_recognizer_vision.dart';

/// 设置页「测试识别」的结果。
class VisionProbeResult {
  const VisionProbeResult.success(this.guess)
      : ok = true,
        message = null;

  const VisionProbeResult.failure(this.message)
      : ok = false,
        guess = null;

  final bool ok;

  /// 失败原因（人话）；成功时为 null。
  final String? message;

  /// 成功时模型返回的结构化结果。
  final ReceiptGuess? guess;
}

/// 测试入口的签名：页面注入假实现就能离线测。
typedef VisionProbeRunner = Future<VisionProbeResult> Function({
  required String baseUrl,
  required String model,
  required String apiKey,
});

/// 连通性自检：拿内置的合成小票，走一遍真实识别链路。
///
/// 验证「地址 + 模型名 + Key + 视觉 + JSON 输出」这条链路通不通，
/// 不保存任何设置、也不发送用户的账单图片。
Future<VisionProbeResult> probeVision({
  required String baseUrl,
  required String model,
  required String apiKey,
  Uint8List? image,
  http.Client? client,
}) async {
  if (apiKey.trim().isEmpty) {
    return const VisionProbeResult.failure('还没填 API Key');
  }

  final recognizer = VisionReceiptRecognizer(
    baseUrl: baseUrl,
    model: model,
    apiKey: apiKey,
    client: client,
  );
  try {
    final guess = await recognizer.recognize(image ?? probeReceiptImage());
    if (guess.amountCents == kProbeAmountCents) {
      return VisionProbeResult.success(guess);
    }
    if (guess.isEmpty) {
      return const VisionProbeResult.failure(
        '接口通了，但没读出测试小票（模型可能不支持图片输入）',
      );
    }
    final read = guess.amountCents == null
        ? '没读出金额'
        : '金额读成了 ¥${(guess.amountCents! / 100).toStringAsFixed(2)}';
    return VisionProbeResult.failure(
      '接口通了，但$read（应为 ¥12.34），换个支持图片的模型试试',
    );
  } on ReceiptRecognitionException catch (error) {
    return VisionProbeResult.failure(error.message);
  } catch (error) {
    // 兜底：留下原始异常，否则只剩「检查网络」一句误导排查方向。
    debugPrint('vision probe failed: $error');
    return const VisionProbeResult.failure('识别请求失败，检查网络后重试');
  } finally {
    await recognizer.close();
  }
}
