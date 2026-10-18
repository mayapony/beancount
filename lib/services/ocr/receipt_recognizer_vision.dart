import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import 'receipt_recognizer.dart';
import 'receipt_vision_settings.dart';

/// 识别失败的可读原因：消息里 MUST NOT 出现 API Key 或图片内容。
class ReceiptRecognitionException implements Exception {
  const ReceiptRecognitionException(this.message, {this.statusCode});

  final String message;
  final int? statusCode;

  @override
  String toString() => 'ReceiptRecognitionException($message)';
}

/// 视觉模型识别：图片 → 文字。
///
/// 走 OpenAI 兼容的 `POST {baseUrl}/chat/completions`，图片以 base64 data URL
/// 放在 `image_url` 里。只负责"图 → 文字"，金额/分类解析仍交给
/// `parseReceiptText`——规则可测、换厂商不影响解析。
class VisionReceiptRecognizer implements ReceiptRecognizer {
  VisionReceiptRecognizer({
    required String baseUrl,
    required String model,
    required String apiKey,
    http.Client? client,
    this.timeout = const Duration(seconds: 20),
  })  : _baseUrl = ReceiptVisionSettings.normalizeBaseUrl(baseUrl),
        _model = ReceiptVisionSettings.normalizeModel(model),
        _apiKey = apiKey.trim(),
        _client = client ?? http.Client(),
        _ownsClient = client == null;

  /// 提示词只要求原样输出：解释、总结都会污染金额解析。
  static const kPrompt = '把图中所有文字按从上到下、从左到右的顺序原样输出，'
      '保留数字与符号；不要解释、不要总结、不要补全、不要加标题。';

  final String _baseUrl;
  final String _model;
  final String _apiKey;
  final http.Client _client;
  final bool _ownsClient;
  final Duration timeout;

  Uri get endpoint => Uri.parse('$_baseUrl/chat/completions');

  @override
  Future<String?> recognizeText(Uint8List bytes) async {
    if (_apiKey.isEmpty) {
      throw const ReceiptRecognitionException('还没配置 API Key');
    }

    final body = jsonEncode({
      'model': _model,
      'stream': false,
      // 只要认字，不需要推理过程：省 token、也省延迟
      'thinking': {'type': 'disabled'},
      'max_tokens': 512,
      'messages': [
        {
          'role': 'user',
          'content': [
            {'type': 'text', 'text': kPrompt},
            {
              'type': 'image_url',
              'image_url': {'url': _dataUrl(bytes)},
            },
          ],
        },
      ],
    });

    final http.Response response;
    try {
      response = await _client
          .post(
            endpoint,
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer $_apiKey',
            },
            body: body,
          )
          .timeout(timeout);
    } on TimeoutException {
      throw const ReceiptRecognitionException('识别超时，稍后再试');
    } on http.ClientException {
      throw const ReceiptRecognitionException('网络不通，检查一下连接');
    }

    if (response.statusCode != 200) {
      throw ReceiptRecognitionException(
        _messageForStatus(response.statusCode),
        statusCode: response.statusCode,
      );
    }

    return _parseContent(response.bodyBytes);
  }

  @override
  Future<void> close() async {
    if (_ownsClient) _client.close();
  }

  String? _parseContent(Uint8List bodyBytes) {
    final Object? decoded;
    try {
      decoded = jsonDecode(utf8.decode(bodyBytes, allowMalformed: true));
    } on FormatException {
      throw const ReceiptRecognitionException('返回内容无法解析');
    }
    if (decoded is! Map<String, dynamic>) {
      throw const ReceiptRecognitionException('返回内容无法解析');
    }
    final choices = decoded['choices'];
    if (choices is! List || choices.isEmpty) return null;
    final first = choices.first;
    if (first is! Map) return null;
    final message = first['message'];
    if (message is! Map) return null;
    final content = message['content'];
    if (content is! String) return null;
    final text = content.trim();
    return text.isEmpty ? null : text;
  }

  static String _messageForStatus(int status) {
    if (status == 401 || status == 403) return 'API Key 无效或没有权限';
    if (status == 429) return '调用太频繁，稍后再试';
    if (status >= 500) return '服务暂时不可用';
    return '识别请求失败（HTTP $status）';
  }

  /// 图片 → data URL。MIME 由文件头推断，相册/相机拿到的字节都没有扩展名。
  static String _dataUrl(Uint8List bytes) =>
      'data:${mimeOf(bytes)};base64,${base64Encode(bytes)}';

  static String mimeOf(Uint8List bytes) {
    bool startsWith(List<int> signature, [int offset = 0]) {
      if (bytes.length < offset + signature.length) return false;
      for (var i = 0; i < signature.length; i++) {
        if (bytes[offset + i] != signature[i]) return false;
      }
      return true;
    }

    if (startsWith(const [0x89, 0x50, 0x4E, 0x47])) return 'image/png';
    if (startsWith(const [0xFF, 0xD8, 0xFF])) return 'image/jpeg';
    if (startsWith(const [0x47, 0x49, 0x46, 0x38])) return 'image/gif';
    if (startsWith(const [0x52, 0x49, 0x46, 0x46]) &&
        startsWith(const [0x57, 0x45, 0x42, 0x50], 8)) {
      return 'image/webp';
    }
    return 'image/jpeg';
  }
}
