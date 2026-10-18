import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:http/http.dart' as http;

import 'receipt_recognizer.dart';
import 'receipt_recognizer_vision.dart';
import 'receipt_vision_settings.dart';

/// 按配置组合当前可用的识别器；不可用时返回 null（面板据此不显示识别能力）。
///
/// 只有「用户显式开启 + 已保存 API Key」才返回识别器：
/// 截图记账只走视觉模型，没有本地 OCR 兜底，也就不存在"偷偷上传"的路径。
/// Web 直接返回 null——浏览器直连第三方端点会被 CORS 拦，不做假承诺。
Future<ReceiptRecognizer?> systemReceiptRecognizer({
  required ReceiptVisionSettingsStore settings,
  required ReceiptApiKeyStore keys,
  http.Client? client,
}) async {
  if (kIsWeb) return null;

  final config = await settings.load();
  if (!config.enabled) return null;

  final apiKey = await keys.read();
  if (apiKey == null || apiKey.isEmpty) return null;

  return VisionReceiptRecognizer(
    baseUrl: config.normalizedBaseUrl,
    model: config.normalizedModel,
    apiKey: apiKey,
    client: client,
  );
}
