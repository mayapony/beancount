import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import 'entry_matching.dart';
import 'receipt_guess.dart';
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

/// 视觉模型识别：图片 → 结构化字段。
///
/// 走 OpenAI 兼容的 `POST {baseUrl}/chat/completions`，图片以 base64 data URL
/// 放在 `image_url` 里，并用 `response_format: json_object` 要求模型只回一个
/// JSON 对象。金额、商家、时间、分类、账户、标签都由模型直接给出，本地只做
/// 「取值是否在词表内」的校验——不再从文字里猜金额。
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

  /// 提示词只描述 JSON 字段与取值词表：解释、总结都会污染结果。
  static final String prompt = [
    '读这张账单或小票图片，只输出一个 JSON 对象，不要解释，不要 markdown 代码块。',
    'amount_cents：整数，本笔实际支付金额，单位「分」（¥18.00 填 1800）；'
        '认不出填 null。',
    'merchant：商家名或商品名；认不出填 null。',
    'paid_at：支付时间，格式 yyyy-MM-dd HH:mm:ss；认不出填 null。',
    'category：从 ${_categoryChoices()} 里选一个；都不合适填 null。',
    'account_hint：从 ${kAccountHints.keys.join('/')} 里选一个；认不出填 null。',
    'tags：从 ${kTagKeywords.keys.join('/')} 里选 0~2 个；没有合适的返回空数组。',
  ].join('\n');

  /// 单笔金额上限（分）：超过这个数基本是把单号认成了金额。
  static const kMaxAmountCents = 100000000;

  final String _baseUrl;
  final String _model;
  final String _apiKey;
  final http.Client _client;
  final bool _ownsClient;
  final Duration timeout;

  Uri get endpoint => Uri.parse('$_baseUrl/chat/completions');

  static String _categoryChoices() => kCategoryKeywords.entries
      .map((entry) => '${entry.key}（${entry.value.take(4).join('、')}）')
      .join('/');

  @override
  Future<ReceiptGuess> recognize(Uint8List bytes) async {
    if (_apiKey.isEmpty) {
      throw const ReceiptRecognitionException('还没配置 API Key');
    }

    final body = jsonEncode({
      'model': _model,
      'stream': false,
      // 只要认字段，不需要推理过程：省 token、也省延迟
      'thinking': {'type': 'disabled'},
      'temperature': 0,
      'max_tokens': 512,
      // OpenAI 兼容的 JSON 模式：模型只能回一个 JSON 对象
      'response_format': {'type': 'json_object'},
      'messages': [
        {
          'role': 'user',
          'content': [
            {'type': 'text', 'text': prompt},
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

    return _parseGuess(response.bodyBytes);
  }

  @override
  Future<void> close() async {
    if (_ownsClient) _client.close();
  }

  /// 从响应里取出 `choices[0].message.content`，再映射成 [ReceiptGuess]。
  ReceiptGuess _parseGuess(Uint8List bodyBytes) {
    final content = _contentOf(bodyBytes);
    if (content == null || content.trim().isEmpty) return ReceiptGuess.empty;

    final decoded = _decodeObject(content);
    final amountCents = _amountCents(decoded['amount_cents']);
    final category = _category(decoded['category']);
    final note = _text(decoded['merchant']);

    return ReceiptGuess(
      amountCents: amountCents,
      categoryName: category,
      tagNames: _tags(decoded['tags']),
      accountName: _account(decoded['account_hint']),
      note: note,
      happenedAt: _paidAt(decoded['paid_at']),
      confidence: amountCents != null
          ? ReceiptConfidence.amount
          : (category != null || note != null
              ? ReceiptConfidence.categoryOnly
              : ReceiptConfidence.none),
    );
  }

  String? _contentOf(Uint8List bodyBytes) {
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
    return content is String ? content.trim() : null;
  }

  /// 模型偶尔会套一层 ```json 代码块，或者多吐一个无关字段；这里都容忍。
  Map<String, dynamic> _decodeObject(String content) {
    var text = content.trim();
    if (text.startsWith('```')) {
      text = text.replaceFirst(RegExp(r'^```[a-zA-Z]*\s*'), '');
      text = text.replaceFirst(RegExp(r'\s*```$'), '');
    }
    final Object? decoded;
    try {
      decoded = jsonDecode(text.trim());
    } on FormatException {
      throw const ReceiptRecognitionException('返回内容不是有效的 JSON');
    }
    if (decoded is! Map<String, dynamic>) {
      throw const ReceiptRecognitionException('返回内容不是有效的 JSON');
    }
    return decoded;
  }

  /// 金额只认「分」为单位的整数/数字/数字字符串；越界一律当没认出来。
  static int? _amountCents(Object? raw) {
    int? cents;
    if (raw is int) {
      cents = raw;
    } else if (raw is num) {
      // 模型偶尔回 18.0 这种浮点：按元换算成分
      cents = (raw * 100).round();
    } else if (raw is String) {
      final text = raw.trim();
      final asInt = int.tryParse(text);
      final asDouble = double.tryParse(text);
      cents = asInt ?? (asDouble == null ? null : (asDouble * 100).round());
    }
    if (cents == null || cents <= 0 || cents > kMaxAmountCents) return null;
    return cents;
  }

  static String? _text(Object? raw) {
    if (raw is! String) return null;
    final text = raw.trim();
    return text.isEmpty ? null : text;
  }

  /// 分类只接受词表内的规范名（含别名归一化），模型自创的一律丢掉。
  static String? _category(Object? raw) {
    final text = _text(raw);
    if (text == null) return null;
    final canonical = canonicalCategoryName(text);
    if (canonical == null) return null;
    for (final name in kCategoryKeywords.keys) {
      if (normalizeName(name) == normalizeName(canonical)) return name;
    }
    return null;
  }

  static String? _account(Object? raw) {
    final text = _text(raw);
    if (text == null) return null;
    final wanted = normalizeName(text);
    for (final name in kAccountHints.keys) {
      if (normalizeName(name) == wanted) return name;
    }
    return null;
  }

  /// 标签只保留词表内的名字，去重后最多 2 个。
  static List<String> _tags(Object? raw) {
    if (raw is! List) return const [];
    final out = <String>[];
    for (final item in raw) {
      final text = _text(item);
      if (text == null) continue;
      final wanted = normalizeName(text);
      for (final name in kTagKeywords.keys) {
        if (normalizeName(name) != wanted) continue;
        if (!out.contains(name)) out.add(name);
        break;
      }
      if (out.length >= 2) break;
    }
    return List<String>.unmodifiable(out);
  }

  static DateTime? _paidAt(Object? raw) {
    final text = _text(raw);
    if (text == null) return null;
    final at = DateTime.tryParse(text);
    if (at == null) return null;
    if (at.year < 2000 || at.year > DateTime.now().year + 1) return null;
    return at;
  }

  static String _messageForStatus(int status) {
    if (status == 401 || status == 403) return 'API Key 无效或没有权限';
    if (status == 404) return '模型或接口不存在（检查服务地址与模型名）';
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
