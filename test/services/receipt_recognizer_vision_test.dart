import 'dart:convert';
import 'dart:typed_data';

import 'package:bean_count/services/ocr/receipt_guess.dart';
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

/// 真实账单（臻汁煌 2026-10-18 18:20:49 -18.00）跑 deepseek-flash 的原始输出。
const _realReceipt = '{"amount_cents": 1800, "merchant": "臻汁煌（金山软件园店）", '
    '"paid_at": "2026-10-18 18:20:49", "category": "餐饮", '
    '"account_hint": "微信", "tags": ["微信支付"]}';

void main() {
  group('请求构造', () {
    test('打 /chat/completions，带 Bearer 与模型名', () async {
      Uri? url;
      final headers = <String, String>{};
      final recognizer = _recognizer(MockClient((request) async {
        url = request.url;
        headers.addAll(request.headers);
        return _ok('{"amount_cents": 100}');
      }));

      await recognizer.recognize(_png);

      expect(url.toString(), 'https://api.deepseek.com/chat/completions');
      expect(headers['Authorization'], 'Bearer sk-test');
      expect(headers['Content-Type'], contains('application/json'));
    });

    test('尾部斜杠归一化，配置可换厂商', () async {
      Uri? url;
      final recognizer = _recognizer(
        MockClient((request) async {
          url = request.url;
          return _ok('{"amount_cents": 1200}');
        }),
        baseUrl: 'https://example.com/v1/',
        model: 'qwen-vl-max',
      );

      await recognizer.recognize(_png);
      expect(url.toString(), 'https://example.com/v1/chat/completions');
    });

    test('要求 JSON 输出，图片走 image_url 的 base64 data URL', () async {
      Map<String, dynamic>? body;
      final recognizer = _recognizer(MockClient((request) async {
        body = jsonDecode(request.body) as Map<String, dynamic>;
        return _ok('{"amount_cents": 100}');
      }));

      await recognizer.recognize(_png);

      expect(body!['model'], 'deepseek-flash');
      expect(body!['stream'], isFalse);
      expect(body!['temperature'], 0);
      expect(body!['response_format'], {'type': 'json_object'});

      final content = ((body!['messages'] as List).first as Map)['content'] as List;
      final text = (content.first as Map)['text'] as String;
      expect(text, contains('amount_cents'));
      expect(text, contains('餐饮'));
      expect(text, contains('微信'));

      final image = content.firstWhere((part) => (part as Map)['type'] == 'image_url');
      final url = ((image as Map)['image_url'] as Map)['url'] as String;
      expect(url, startsWith('data:image/png;base64,'));
      expect(url, endsWith(base64Encode(_png)));
    });

    test('JPEG 头推断成 image/jpeg', () async {
      String? url;
      final recognizer = _recognizer(MockClient((request) async {
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        final content = ((body['messages'] as List).first as Map)['content'] as List;
        final image = content.firstWhere((part) => (part as Map)['type'] == 'image_url');
        url = ((image as Map)['image_url'] as Map)['url'] as String;
        return _ok('{"amount_cents": 100}');
      }));

      await recognizer.recognize(_jpeg);
      expect(url, startsWith('data:image/jpeg;base64,'));
    });

    test('Key 不进请求体，也不会出现在请求日志里', () async {
      String? raw;
      final recognizer = _recognizer(MockClient((request) async {
        raw = request.body;
        return _ok('{"amount_cents": 100}');
      }));

      await recognizer.recognize(_png);
      expect(raw, isNot(contains('sk-test')));
    });

    test('空 Key 直接拒绝，不发请求', () async {
      var called = false;
      final recognizer = _recognizer(
        MockClient((request) async {
          called = true;
          return _ok('{"amount_cents": 100}');
        }),
        apiKey: '   ',
      );

      await expectLater(
        recognizer.recognize(_png),
        throwsA(isA<ReceiptRecognitionException>()),
      );
      expect(called, isFalse);
    });
  });

  group('结构化结果映射', () {
    Future<ReceiptGuess> guessOf(String content) =>
        _recognizer(MockClient((_) async => _ok(content))).recognize(_png);

    test('真实账单：金额/商家/时间/分类/账户/标签都对', () async {
      final guess = await guessOf(_realReceipt);

      expect(guess.amountCents, 1800);
      expect(guess.note, '臻汁煌（金山软件园店）');
      expect(guess.categoryName, '餐饮');
      expect(guess.accountName, '微信');
      expect(guess.tagNames, ['微信支付']);
      expect(guess.happenedAt, DateTime(2026, 10, 18, 18, 20, 49));
      expect(guess.confidence, ReceiptConfidence.amount);
      expect(guess.hasAmount, isTrue);
    });

    test('模型多吐一个无关字段也不影响（真实响应里出现过）', () async {
      final guess = await guessOf('{"type": "json_object", "amount_cents": 1234}');
      expect(guess.amountCents, 1234);
    });

    test('```json 代码块也能解', () async {
      final guess = await guessOf('```json\n{"amount_cents": 4450}\n```');
      expect(guess.amountCents, 4450);
    });

    test('金额容忍浮点与数字字符串', () async {
      expect((await guessOf('{"amount_cents": 18.0}')).amountCents, 1800);
      expect((await guessOf('{"amount_cents": "1850"}')).amountCents, 1850);
      expect((await guessOf('{"amount_cents": "18.50"}')).amountCents, 1850);
    });

    test('金额越界或非正数按没认出来处理', () async {
      expect((await guessOf('{"amount_cents": 0}')).amountCents, isNull);
      expect((await guessOf('{"amount_cents": -1800}')).amountCents, isNull);
      expect(
        (await guessOf('{"amount_cents": 200000000}')).amountCents,
        isNull,
      );
      expect((await guessOf('{"amount_cents": "abc"}')).amountCents, isNull);
      expect((await guessOf('{"amount_cents": null}')).amountCents, isNull);
    });

    test('分类只认词表：别名归一化，自创的丢掉', () async {
      expect((await guessOf('{"category": "吃饭"}')).categoryName, '餐饮');
      expect((await guessOf('{"category": "交通"}')).categoryName, '交通');
      expect((await guessOf('{"category": "饮品"}')).categoryName, isNull);
      expect((await guessOf('{"category": 42}')).categoryName, isNull);
    });

    test('账户只认规范名', () async {
      expect((await guessOf('{"account_hint": "支付宝"}')).accountName, '支付宝');
      expect(
        (await guessOf('{"account_hint": "微信零钱"}')).accountName,
        isNull,
        reason: '只接受词表里的规范名，不做模糊匹配',
      );
    });

    test('标签去重、过滤词表外、最多两个', () async {
      final guess =
          await guessOf('{"tags": ["咖啡", "咖啡", "外卖", "打车", "超市"]}');
      expect(guess.tagNames, ['咖啡', '外卖']);
    });

    test('没有金额时置信度降级但仍给其它字段', () async {
      final guess = await guessOf('{"merchant": "某店", "category": "购物"}');
      expect(guess.amountCents, isNull);
      expect(guess.note, '某店');
      expect(guess.confidence, ReceiptConfidence.categoryOnly);
    });

    test('时间解析不了就丢掉', () async {
      expect((await guessOf('{"paid_at": "昨天"}')).happenedAt, isNull);
      expect((await guessOf('{"paid_at": 20261018}')).happenedAt, isNull);
    });

    test('空内容与空 choices 返回空结果，不抛异常', () async {
      expect((await guessOf('   ')).isEmpty, isTrue);

      final recognizer = _recognizer(
        MockClient((_) async => http.Response('{"choices":[]}', 200)),
      );
      expect((await recognizer.recognize(_png)).isEmpty, isTrue);
    });

    test('内容不是 JSON 抛可读异常', () async {
      await expectLater(
        guessOf('合计 ¥44.50'),
        throwsA(
          isA<ReceiptRecognitionException>().having(
            (e) => e.message,
            'message',
            contains('JSON'),
          ),
        ),
      );
    });

    test('响应体不是 JSON 抛可读异常', () async {
      final recognizer = _recognizer(
        MockClient((_) async => http.Response('<html>oops</html>', 200)),
      );
      await expectLater(
        recognizer.recognize(_png),
        throwsA(
          isA<ReceiptRecognitionException>().having(
            (e) => e.message,
            'message',
            contains('无法解析'),
          ),
        ),
      );
    });
  });

  group('失败映射', () {
    test('401 提示 Key 无效，消息里不含 Key', () async {
      final recognizer = _recognizer(
        MockClient((_) async => http.Response('unauthorized', 401)),
      );
      try {
        await recognizer.recognize(_png);
        fail('应该抛异常');
      } on ReceiptRecognitionException catch (e) {
        expect(e.statusCode, 401);
        expect(e.message, contains('Key'));
        expect(e.message, isNot(contains('sk-test')));
      }
    });

    test('404 提示检查地址与模型名', () async {
      final recognizer = _recognizer(
        MockClient((_) async => http.Response('', 404)),
      );
      await expectLater(
        recognizer.recognize(_png),
        throwsA(
          isA<ReceiptRecognitionException>()
              .having((e) => e.statusCode, 'status', 404)
              .having((e) => e.message, 'message', contains('模型')),
        ),
      );
    });

    test('429 提示太频繁', () async {
      final recognizer = _recognizer(
        MockClient((_) async => http.Response('', 429)),
      );
      await expectLater(
        recognizer.recognize(_png),
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
        recognizer.recognize(_png),
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
          return _ok('{"amount_cents": 100}');
        }),
        timeout: const Duration(milliseconds: 20),
      );
      await expectLater(
        recognizer.recognize(_png),
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
        recognizer.recognize(_png),
        throwsA(
          isA<ReceiptRecognitionException>()
              .having((e) => e.message, 'message', contains('网络')),
        ),
      );
    });
  });

  test('close 只关自己创建的 client', () async {
    final client = MockClient((_) async => _ok('{}'));
    final recognizer = _recognizer(client);
    await recognizer.close();
    // 注入的 client 仍可继续使用（由调用方负责关闭）
    final response = await client.get(Uri.parse('https://example.com'));
    expect(response.statusCode, 200);
  });
}
