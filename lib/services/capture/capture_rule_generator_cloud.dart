library;

import 'dart:async';
import 'dart:convert';
import 'dart:io' show TlsException;
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show debugPrint, kIsWeb;
import 'package:http/http.dart' as http;

import '../ocr/receipt_vision_settings.dart';
import 'capture_candidate.dart';
import 'capture_rule.dart';
import 'capture_rule_generator.dart';

/// 规则生成失败的可读原因；消息里 MUST NOT 出现 API Key 或树快照全文。
class RuleGenerationException implements Exception {
  const RuleGenerationException(this.message);

  final String message;

  @override
  String toString() => 'RuleGenerationException($message)';
}

/// 云端规则生成：OpenAI 兼容的 `chat/completions`，要求模型只回一个 JSON 规则。
class CloudCaptureRuleGenerator implements CaptureRuleGenerator {
  CloudCaptureRuleGenerator({
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

  final String _baseUrl;
  final String _model;
  final String _apiKey;
  final http.Client _client;
  final bool _ownsClient;
  final Duration timeout;

  static final String prompt = [
    '根据脱敏后的控件树快照与真值金额，输出一个 JSON 对象，描述怎么从这页提取金额。',
    '只输出 JSON，不要解释，不要 markdown 代码块。',
    'amount_strategy：regex / adjacent_label 二选一。',
    'amount_pattern：amount_strategy 为 regex 时必填，正则的第一捕获组是金额数字。',
    'adjacent_label：amount_strategy 为 adjacent_label 时必填，金额旁边的标签文字。',
    'exclude_keywords：字符串数组，命中的文本不当作支付（如余额、优惠）。',
    'direction：expense / income / refund 三选一。',
  ].join('\n');

  @override
  Future<CaptureRule> generate(CaptureRuleGenerationRequest request) async {
    if (_apiKey.isEmpty) {
      throw const RuleGenerationException('还没配置 API Key');
    }

    final body = jsonEncode({
      'model': _model,
      'stream': false,
      'thinking': {'type': 'disabled'},
      'temperature': 0,
      'max_tokens': 512,
      'response_format': {'type': 'json_object'},
      'messages': [
        {
          'role': 'user',
          'content': [
            {'type': 'text', 'text': prompt},
            {'type': 'text', 'text': '真值金额（分）：${request.amountCents}'},
            {'type': 'text', 'text': '脱敏树快照：\n${request.desensitizedTree}'},
          ],
        },
      ],
    });

    final response = await _post(body);
    if (response.statusCode != 200) {
      throw RuleGenerationException(_messageForStatus(response.statusCode));
    }
    return _parseRule(response.bodyBytes, request);
  }

  void close() {
    if (_ownsClient) _client.close();
  }

  Future<http.Response> _post(String body) async {
    try {
      return await _client
          .post(
            Uri.parse('$_baseUrl/chat/completions'),
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer $_apiKey',
            },
            body: body,
          )
          .timeout(timeout);
    } on TimeoutException {
      throw const RuleGenerationException('生成超时，稍后再试');
    } on http.ClientException {
      throw const RuleGenerationException('网络不通，检查一下连接');
    } on TlsException catch (error) {
      debugPrint('rule generate: TLS 失败 $error');
      throw const RuleGenerationException('安全连接没建立起来（证书没过）');
    }
  }

  CaptureRule _parseRule(
    Uint8List bodyBytes,
    CaptureRuleGenerationRequest request,
  ) {
    final content = _contentOf(bodyBytes);
    if (content == null || content.trim().isEmpty) {
      throw const RuleGenerationException('模型没有返回内容');
    }
    final decoded = _decodeObject(content);
    final strategy = _strategy(decoded['amount_strategy']);
    final direction = _direction(decoded['direction']);

    return CaptureRule(
      id: 'rule-${DateTime.now().microsecondsSinceEpoch}',
      packageName: request.packageName,
      target: request.target,
      surfaceFingerprint: request.surfaceFingerprint,
      direction: direction,
      amountStrategy: strategy,
      amountPattern: _text(decoded['amount_pattern']),
      adjacentLabel: _text(decoded['adjacent_label']),
      excludeKeywords: _strings(decoded['exclude_keywords']),
      version: 1,
      tier: CaptureRuleTier.pending,
      confirmations: 0,
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );
  }

  String? _contentOf(Uint8List bodyBytes) {
    final Object? decoded;
    try {
      decoded = jsonDecode(utf8.decode(bodyBytes, allowMalformed: true));
    } on FormatException {
      throw const RuleGenerationException('返回内容无法解析');
    }
    if (decoded is! Map<String, dynamic>) {
      throw const RuleGenerationException('返回内容无法解析');
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
      throw const RuleGenerationException('返回内容不是有效的 JSON');
    }
    if (decoded is! Map<String, dynamic>) {
      throw const RuleGenerationException('返回内容不是有效的 JSON');
    }
    return decoded;
  }

  static AmountStrategy _strategy(Object? raw) {
    switch (raw?.toString()) {
      case 'regex':
        return AmountStrategy.regex;
      case 'adjacent_label':
        return AmountStrategy.adjacentLabel;
      default:
        return AmountStrategy.regex;
    }
  }

  static CaptureDirection _direction(Object? raw) {
    switch (raw?.toString()) {
      case 'income':
        return CaptureDirection.income;
      case 'refund':
        return CaptureDirection.refund;
      default:
        return CaptureDirection.expense;
    }
  }

  static String? _text(Object? raw) {
    if (raw is! String) return null;
    final text = raw.trim();
    return text.isEmpty ? null : text;
  }

  static List<String> _strings(Object? raw) {
    if (raw is! List) return const [];
    return raw.whereType<String>().toList(growable: false);
  }

  static String _messageForStatus(int status) {
    if (status == 401 || status == 403) return 'API Key 无效或没有权限';
    if (status == 404) return '模型或接口不存在（检查服务地址与模型名）';
    if (status == 429) return '调用太频繁，稍后再试';
    if (status >= 500) return '服务暂时不可用';
    return '规则生成失败（HTTP $status）';
  }
}

/// 按配置组合当前可用的规则生成器；不可用时返回 null（不生成、不上传）。
///
/// 只有「用户显式开启 + 已保存 API Key」才返回生成器，与视觉识别共用同一套
/// 配置与密钥；Web 直接返回 null。
Future<CaptureRuleGenerator?> systemCaptureRuleGenerator({
  required ReceiptVisionSettingsStore settings,
  required ReceiptApiKeyStore keys,
  http.Client? client,
}) async {
  if (kIsWeb) return null;

  final config = await settings.load();
  if (!config.enabled) return null;

  final apiKey = await keys.read();
  if (apiKey == null || apiKey.isEmpty) return null;

  return CloudCaptureRuleGenerator(
    baseUrl: config.normalizedBaseUrl,
    model: config.normalizedModel,
    apiKey: apiKey,
    client: client,
  );
}
