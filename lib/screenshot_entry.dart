import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:path_provider/path_provider.dart';

import 'data/db/app_database.dart';
import 'data/db/connection.dart';
import 'data/repositories/app_state_repository.dart';
import 'services/ocr/receipt_parser.dart';
import 'services/ocr/receipt_recognizer.dart';
import 'services/ocr/receipt_recognizer_factory.dart';
import 'services/ocr/receipt_vision_settings.dart';
import 'services/screenshot/pending_entry.dart';

/// 后台识别入口：由 `ScreenshotService` 里的 headless FlutterEngine 运行。
///
/// 只做一件事——收到截图字节 → 复用现有识别器 → 把结果写进 `app_state`。
/// 不碰 UI；通知由 Kotlin 侧根据返回值发。
@pragma('vm:entry-point')
void screenshotEntry() {
  WidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('com.jindou.bean_count/screenshot');
  channel.setMethodCallHandler((call) async {
    if (call.method != 'recognize') return null;
    final args = call.arguments;
    final bytes = args is Map ? args['bytes'] : null;
    if (bytes is! Uint8List) return {'ok': false};
    final path = args is Map ? args['path'] as String? : null;
    return _recognize(bytes, path);
  });
  channel.invokeMethod<void>('ready');
}

Future<Map<String, Object?>> _recognize(Uint8List bytes, String? url) async {
  final db = AppDatabase(openDatabaseConnection());
  final state = AppStateRepository(db);
  final store = PendingScreenshotEntryStore(state);
  final now = DateTime.now();
  String? imagePath;

  try {
    // MediaStore 的 content:// URI 在 UI 引擎里读不了；落一份临时文件随草稿带走。
    imagePath = await _saveTempImage(bytes, now);

    final recognizer = await systemReceiptRecognizer(
      settings: ReceiptVisionSettingsStore(state),
      keys: SecureReceiptApiKeyStore(),
    );
    if (recognizer == null) {
      await store.write(
        PendingScreenshotEntry(
          id: 'shot-${now.microsecondsSinceEpoch}',
          createdAt: now,
          imagePath: imagePath,
          error: '视觉识别未开启，可在设置里配置 API Key',
        ),
      );
      return {'ok': false};
    }

    ReceiptGuess guess;
    try {
      guess = await recognizeReceipt(recognizer, bytes);
    } finally {
      await recognizer.close();
    }

    final usable = guess.hasAmount || guess.categoryName != null || guess.note != null;
    await store.write(
      PendingScreenshotEntry(
        id: 'shot-${now.microsecondsSinceEpoch}',
        createdAt: now,
        guess: usable ? guess : null,
        imagePath: imagePath,
        error: usable ? null : '没认出金额，点击手动记',
      ),
    );
    return {
      'ok': usable,
      'amount_cents': guess.amountCents,
      'category': guess.categoryName,
      'note': guess.note,
      'source': url,
    };
  } catch (error) {
    await store.write(
      PendingScreenshotEntry(
        id: 'shot-${now.microsecondsSinceEpoch}',
        createdAt: now,
        imagePath: imagePath,
        error: '识别失败，可以手动记',
      ),
    );
    return {'ok': false};
  } finally {
    await db.close();
  }
}

Future<String?> _saveTempImage(Uint8List bytes, DateTime now) async {
  try {
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/screenshot_${now.microsecondsSinceEpoch}.jpg');
    await file.writeAsBytes(bytes, flush: true);
    return file.path;
  } catch (_) {
    return null;
  }
}
