import 'dart:convert';
import 'dart:io' show HandshakeException;
import 'dart:typed_data';

import 'package:bean_count/services/ocr/probe_receipt_image.dart';
import 'package:bean_count/services/ocr/vision_probe.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

final _png = Uint8List.fromList([
  0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, //
  0x00, 0x00, 0x00, 0x0D, 0x49, 0x48, 0x44, 0x52,
]);

http.Response _ok(String content) => http.Response.bytes(
      utf8.encode(jsonEncode({
        'choices': [
          {
            'message': {'role': 'assistant', 'content': content},
          },
        ],
      })),
      200,
    );

Future<VisionProbeResult> _probe(MockClient client) => probeVision(
      baseUrl: 'https://api.deepseek.com',
      model: 'deepseek-flash',
      apiKey: 'sk-test',
      image: _png,
      client: client,
    );

void main() {
  test('读出 12.34 才算通过', () async {
    final result = await _probe(MockClient(
      (_) async => _ok(
        '{"amount_cents": 1234, "merchant": "DEMO MARKET", "category": "购物"}',
      ),
    ));

    expect(result.ok, isTrue);
    expect(result.message, isNull);
    expect(result.guess?.amountCents, kProbeAmountCents);
  });

  test('接口通但金额读错：明确说清读成了多少', () async {
    final result = await _probe(
      MockClient((_) async => _ok('{"amount_cents": 999}')),
    );

    expect(result.ok, isFalse);
    expect(result.message, contains('¥9.99'));
    expect(result.message, contains('¥12.34'));
  });

  test('模型不支持图片：什么都认不出时提示换模型', () async {
    final result = await _probe(MockClient((_) async => _ok('{}')));

    expect(result.ok, isFalse);
    expect(result.message, contains('不支持图片'));
  });

  test('401 直接给出 Key 无效', () async {
    final result = await _probe(
      MockClient((_) async => http.Response('unauthorized', 401)),
    );

    expect(result.ok, isFalse);
    expect(result.message, contains('API Key 无效'));
  });

  test('模型名写错时提示检查地址与模型', () async {
    final result = await _probe(
      MockClient((_) async => http.Response('', 404)),
    );

    expect(result.ok, isFalse);
    expect(result.message, contains('模型'));
  });

  test('返回不是 JSON 时提示无法解析，而不是假装成功', () async {
    final result = await _probe(
      MockClient((_) async => _ok('我识别不了这张图')),
    );

    expect(result.ok, isFalse);
    expect(result.message, contains('JSON'));
  });

  test('没填 Key 时不发请求', () async {
    var called = false;
    final result = await probeVision(
      baseUrl: 'https://api.deepseek.com',
      model: 'deepseek-flash',
      apiKey: '  ',
      image: _png,
      client: MockClient((_) async {
        called = true;
        return _ok('{"amount_cents": 1234}');
      }),
    );

    expect(result.ok, isFalse);
    expect(result.message, contains('API Key'));
    expect(called, isFalse);
  });

  test('网络异常给人话提示', () async {
    final result = await _probe(
      MockClient((_) async => throw http.ClientException('boom')),
    );

    expect(result.ok, isFalse);
    expect(result.message, contains('网络'));
  });

  test('证书不过时说证书，而不是笼统的「检查网络」', () async {
    // 真实事故：TLS 握手失败不会被 http 包包装成 ClientException，
    // 以前会落进 catch-all，界面只说「检查网络」，把 VPN 这个真凶藏了。
    final result = await _probe(
      MockClient(
        (_) async => throw const HandshakeException(
          'CERTIFICATE_VERIFY_FAILED: self signed certificate',
        ),
      ),
    );

    expect(result.ok, isFalse);
    expect(result.message, contains('证书'));
    expect(result.message, isNot(contains('检查网络后重试')));
  });

  test('内置小票是一张可用的 PNG', () {
    final bytes = probeReceiptImage();

    expect(bytes.sublist(0, 4), [0x89, 0x50, 0x4E, 0x47]);
    // PNG 头里带尺寸：宽 340、高 220（大端 4 字节）
    expect(
      (bytes[16] << 24) | (bytes[17] << 16) | (bytes[18] << 8) | bytes[19],
      kProbeImageWidth,
    );
    expect(
      (bytes[20] << 24) | (bytes[21] << 16) | (bytes[22] << 8) | bytes[23],
      kProbeImageHeight,
    );
    expect(bytes.length, greaterThan(1000));
  });
}
