import 'package:bean_count/data/db/app_database.dart';
import 'package:bean_count/data/db/connection.dart';
import 'package:bean_count/data/repositories/app_state_repository.dart';
import 'package:bean_count/pages/shell.dart';
import 'dart:convert';
import 'dart:typed_data';

import 'package:bean_count/services/ocr/receipt_recognizer.dart';
import 'package:bean_count/services/ocr/receipt_recognizer_vision.dart';
import 'package:bean_count/services/ocr/receipt_vision_settings.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:bean_count/services/screenshot/pending_entry.dart';
import 'package:bean_count/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

/// 设备端验证「后台识别结果 → 面板预填」这条链路。
///
/// 不调真接口：识别结果用词表直接构造，等同于后台引擎写进 app_state 的内容；
/// 重点是 JSON 落库、冷启动读取与面板预填在真机/模拟器上确实成立。
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('待处理识别写入数据库后，启动即预填并清空', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.75;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final db = AppDatabase(openInMemoryConnection());
    addTearDown(db.close);
    final state = AppStateRepository(db);
    await db.select(db.appState).get();

    final store = PendingScreenshotEntryStore(state);

    // 与后台引擎同一套链路：MockClient 冒充视觉模型 → 解析 → 写待处理 JSON。
    final recognizer = VisionReceiptRecognizer(
      baseUrl: 'https://api.deepseek.com/',
      model: 'deepseek-flash',
      apiKey: 'test-key',
      client: MockClient((request) async {
        return http.Response.bytes(
          utf8.encode(jsonEncode({
            'choices': [
              {
                'message': {
                  'role': 'assistant',
                  'content': '金豆餐厅消费小票\n牛肉面 ¥38.50\n可乐 ¥6.00\n合计 ¥44.50',
                },
              },
            ],
          })),
          200,
          headers: {'content-type': 'application/json'},
        );
      }),
    );
    final guess = await recognizeReceipt(
      recognizer,
      Uint8List.fromList([1, 2, 3]),
    );
    await recognizer.close();

    expect(guess.amountCents, 4450);
    await store.write(
      PendingScreenshotEntry(
        id: 'device-shot-1',
        createdAt: DateTime(2026, 10, 18, 12),
        guess: guess,
      ),
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: buildBeanTheme(Brightness.light),
        home: ShellPage(
          database: db,
          visionKeys: MemoryReceiptApiKeyStore(),
        ),
      ),
    );
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 120));
    }
    await tester.pumpAndSettle();

    expect(find.text('记一笔'), findsOneWidget);
    expect(find.text('44.50'), findsWidgets);
    expect(find.textContaining('金豆餐厅'), findsWidgets);
    expect(await store.peek(), isNull, reason: '消费后必须清空，避免重复弹');
  });
}
