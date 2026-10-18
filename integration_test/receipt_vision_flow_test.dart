import 'dart:convert';
import 'dart:typed_data';

import 'package:bean_count/data/db/app_database.dart';
import 'package:bean_count/data/db/connection.dart';
import 'package:bean_count/data/repositories/account_repository.dart';
import 'package:bean_count/data/repositories/category_repository.dart';
import 'package:bean_count/services/attachments/image_picker_service.dart';
import 'package:bean_count/services/ocr/receipt_recognizer.dart';
import 'package:bean_count/services/ocr/receipt_recognizer_vision.dart';
import 'package:bean_count/widgets/quick_entry_sheet.dart';
import 'package:bean_count/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:integration_test/integration_test.dart';

/// 设备端走一遍视觉识别链路：HTTP 请求构造 → 响应解析 → 面板预填。
///
/// 不调真接口（真 Key 不进仓库，CI 也不该依赖第三方可用性）：
/// 用 MockClient 冒充 DeepSeek，仍在设备上真实跑 base64、JSON 与面板交互。
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  // 一张 1×1 PNG：只验证链路，不需要真小票——认字由云端负责
  final pngBytes = base64Decode(
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==',
  );

  testWidgets('视觉识别结果预填金额、分类与备注', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.75;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    Uri? requested;
    Map<String, dynamic>? sentBody;
    final recognizer = VisionReceiptRecognizer(
      baseUrl: 'https://api.deepseek.com/',
      model: 'deepseek-flash',
      apiKey: 'test-key',
      client: MockClient((request) async {
        requested = request.url;
        sentBody = jsonDecode(request.body) as Map<String, dynamic>;
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

    final guess = await recognizeReceipt(recognizer, Uint8List.fromList(pngBytes));
    expect(requested?.path, '/chat/completions', reason: '尾部斜杠被归一化');
    expect(sentBody?['model'], 'deepseek-flash');
    expect(
      jsonEncode(sentBody),
      isNot(contains('test-key')),
      reason: 'Key 只在 Header 里，不进请求体',
    );
    expect(guess.amountCents, 4450);
    expect(guess.categoryName, '餐饮');
    await recognizer.close();

    // 用识别结果驱动面板
    final db = AppDatabase(openInMemoryConnection());
    final accounts = AccountRepository(db);
    final categories = CategoryRepository(db);
    await db.select(db.categories).get();
    final allAccounts = await accounts.withBalances();
    final allCategories = await categories.allCategories();

    QuickEntryDraft? submitted;
    await tester.pumpWidget(
      MaterialApp(
        theme: buildBeanTheme(Brightness.light),
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () => showModalBottomSheet<void>(
                  context: context,
                  isScrollControlled: true,
                  builder: (_) => QuickEntrySheet(
                    categories: allCategories,
                    accounts: allAccounts,
                    pickImage: (_) async => PickedImage(
                      bytes: Uint8List.fromList(pngBytes),
                      fileName: 'receipt.png',
                    ),
                    recognizeReceipt: (bytes) async => guess,
                    onSubmit: (draft) async {
                      submitted = draft;
                      return null;
                    },
                  ),
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('从相册添加'));
    await tester.pumpAndSettle();

    expect(find.text('44.50'), findsWidgets, reason: '金额被预填');
    expect(find.textContaining('金豆餐厅'), findsWidgets, reason: '备注被预填');

    await tester.tap(find.text('完成'));
    await tester.pumpAndSettle();

    expect(submitted?.amount, 44.5);
    expect(submitted?.category?.name, '餐饮');
    expect(submitted?.note, '金豆餐厅');
    await db.close();
  });
}
