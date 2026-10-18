import 'dart:convert';
import 'dart:typed_data';

import 'package:bean_count/services/ocr/receipt_parser.dart';
import 'package:bean_count/services/ocr/receipt_recognizer.dart';
import 'package:bean_count/services/ocr/receipt_recognizer_vision.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// 1×1 PNG 头 + 少量填充：只关心 MIME 推断与 base64，不需要真图。
final _png = Uint8List.fromList([
  0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, //
  0x00, 0x00, 0x00, 0x0D, 0x49, 0x48, 0x44, 0x52,
]);

final _jpeg = Uint8List.fromList([0xFF, 0xD8, 0xFF, 0xE0, 0x00, 0x10]);

http.Response _ok(String content) => http.Response.bytes(
      utf8.encode(jsonEncode({
        'choices': [
          {
            'message': {'role': 'assistant', 'content': content},
          },
        ],
      })),
      200,
      headers: {'content-type': 'application/json'},
    );

VisionReceiptRecognizer _recognizer(
  MockClient client, {
  String baseUrl = 'https://api.deepseek.com',
  String model = 'deepseek-flash',
  String apiKey = 'sk-test',
  Duration timeout = const Duration(seconds: 20),
}) =>
    VisionReceiptRecognizer(
      baseUrl: baseUrl,
      model: model,
      apiKey: apiKey,
      client: client,
      timeout: timeout,
    );

void main() {
  group('请求构造', () {
    test('打 /chat/completions，带 Bearer 与模型名', () async {
      Uri? url;
      final headers = <String, String>{};
      final recognizer = _recognizer(MockClient((request) async {
        url = request.url;
        headers.addAll(request.headers);
        return _ok('合计 ¥44.50');
      }));

      await recognizer.recognizeText(_png);

      expect(url.toString(), 'https://api.deepseek.com/chat/completions');
      expect(headers['Authorization'], 'Bearer sk-test');
      expect(headers['Content-Type'], contains('application/json'));
    });

    test('尾部斜杠归一化，配置可换厂商', () async {
      Uri? url;
      final recognizer = _recognizer(
        MockClient((request) async {
          url = request.url;
          return _ok('¥12.00');
        }),
        baseUrl: 'https://example.com/v1/',
        model: 'qwen-vl-max',
      );

      await recognizer.recognizeText(_png);
      expect(url.toString(), 'https://example.com/v1/chat/completions');
    });

    test('图片走 image_url 的 base64 data URL，MIME 由文件头推断', () async {
      Map<String, dynamic>? body;
      final recognizer = _recognizer(MockClient((request) async {
        body = jsonDecode(request.body) as Map<String, dynamic>;
        return _ok('¥1.00');
      }));

      await recognizer.recognizeText(_png);

      final messages = body!['messages'] as List;
      final content = (messages.first as Map)['content'] as List;
      final image = content.firstWhere((part) => (part as Map)['type'] == 'image_url');
      final url = ((image as Map)['image_url'] as Map)['url'] as String;
      expect(url, startsWith('data:image/png;base64,'));
      expect(url, endsWith(base64Encode(_png)));
      expect(body!['model'], 'deepseek-flash');
      expect(body!['stream'], isFalse);
    });

    test('JPEG 头推断成 image/jpeg', () async {
      String? url;
      final recognizer = _recognizer(MockClient((request) async {
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        final content = ((body['messages'] as List).first as Map)['content'] as List;
        final image = content.firstWhere((part) => (part as Map)['type'] == 'image_url');
        url = ((image as Map)['image_url'] as Map)['url'] as String;
        return _ok('¥1.00');
      }));

      await recognizer.recognizeText(_jpeg);
      expect(url, startsWith('data:image/jpeg;base64,'));
    });

    test('Key 不进请求体，也不会出现在请求日志里', () async {
      String? raw;
      final recognizer = _recognizer(MockClient((request) async {
        raw = request.body;
        return _ok('¥1.00');
      }));

      await recognizer.recognizeText(_png);
      expect(raw, isNot(contains('sk-test')));
    });

    test('空 Key 直接拒绝，不发请求', () async {
      var called = false;
      final recognizer = _recognizer(
        MockClient((request) async {
          called = true;
          return _ok('');
        }),
        apiKey: '   ',
      );

      await expectLater(
        recognizer.recognizeText(_png),
        throwsA(isA<ReceiptRecognitionException>()),
      );
      expect(called, isFalse);
    });
  });

  group('响应解析', () {
    test('200 取 choices[0].message.content', () async {
      final recognizer = _recognizer(
        MockClient((_) async => _ok('  合计 ¥44.50  ')),
      );
      expect(await recognizer.recognizeText(_png), '合计 ¥44.50');
    });

    test('空内容返回 null', () async {
      final recognizer = _recognizer(MockClient((_) async => _ok('   ')));
      expect(await recognizer.recognizeText(_png), isNull);
    });

    test('没有 choices 返回 null', () async {
      final recognizer = _recognizer(
        MockClient((_) async => http.Response('{"choices":[]}', 200)),
      );
      expect(await recognizer.recognizeText(_png), isNull);
    });

    test('畸形 JSON 抛可读异常', () async {
      final recognizer = _recognizer(
        MockClient((_) async => http.Response('<html>oops</html>', 200)),
      );
      await expectLater(
        recognizer.recognizeText(_png),
        throwsA(
          isA<ReceiptRecognitionException>().having(
            (e) => e.message,
            'message',
            contains('无法解析'),
          ),
        ),
      );
    });

    test('401 提示 Key 无效，消息里不含 Key', () async {
      final recognizer = _recognizer(
        MockClient((_) async => http.Response('unauthorized', 401)),
      );
      try {
        await recognizer.recognizeText(_png);
        fail('应该抛异常');
      } on ReceiptRecognitionException catch (e) {
        expect(e.statusCode, 401);
        expect(e.message, contains('Key'));
        expect(e.message, isNot(contains('sk-test')));
      }
    });

    test('429 提示太频繁', () async {
      final recognizer = _recognizer(
        MockClient((_) async => http.Response('', 429)),
      );
      await expectLater(
        recognizer.recognizeText(_png),
        throwsA(
          isA<ReceiptRecognitionException>()
              .having((e) => e.statusCode, 'status', 429)
              .having((e) => e.message, 'message', contains('频繁')),
        ),
      );
    });

    test('5xx 提示服务不可用', () async {
      final recognizer = _recognizer(
        MockClient((_) async => http.Response('', 503)),
      );
      await expectLater(
        recognizer.recognizeText(_png),
        throwsA(
          isA<ReceiptRecognitionException>()
              .having((e) => e.message, 'message', contains('暂时不可用')),
        ),
      );
    });

    test('超时抛可读异常', () async {
      final recognizer = _recognizer(
        MockClient((_) async {
          await Future<void>.delayed(const Duration(milliseconds: 200));
          return _ok('¥1.00');
        }),
        timeout: const Duration(milliseconds: 20),
      );
      await expectLater(
        recognizer.recognizeText(_png),
        throwsA(
          isA<ReceiptRecognitionException>()
              .having((e) => e.message, 'message', contains('超时')),
        ),
      );
    });

    test('网络异常翻译成可读提示', () async {
      final recognizer = _recognizer(
        MockClient((_) async => throw http.ClientException('boom')),
      );
      await expectLater(
        recognizer.recognizeText(_png),
        throwsA(
          isA<ReceiptRecognitionException>()
              .having((e) => e.message, 'message', contains('网络')),
        ),
      );
    });
  });

  test('识别出的文字交给 parseReceiptText 能填对金额与分类', () async {
    final recognizer = _recognizer(
      MockClient(
        (_) async => _ok('金豆餐厅 消费小票\n牛肉面 ¥38.50\n合计 ¥44.50'),
      ),
    );

    final guess = await recognizeReceipt(recognizer, _png);
    expect(guess.amountCents, 4450);
    expect(guess.categoryName, '餐饮');
    expect(guess.confidence, ReceiptConfidence.amount);
  });

  test('close 只关自己创建的 client', () async {
    final client = MockClient((_) async => _ok(''));
    final recognizer = _recognizer(client);
    await recognizer.close();
    // 注入的 client 仍可继续使用（由调用方负责关闭）
    final response = await client.get(Uri.parse('https://example.com'));
    expect(response.statusCode, 200);
  });
}
