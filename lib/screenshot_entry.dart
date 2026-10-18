import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:path_provider/path_provider.dart';

import 'data/db/app_database.dart';
import 'data/db/connection.dart';
import 'data/repositories/app_state_repository.dart';
import 'services/ocr/receipt_guess.dart';
import 'services/ocr/receipt_recognizer_factory.dart';
import 'services/ocr/receipt_recognizer_vision.dart';
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
    if (bytes is! Uint8List) return {'ok': false, 'error': '截图字节无效'};
    final recognitionBytes = args is Map ? args['recognitionBytes'] : null;
    final path = args is Map ? args['path'] as String? : null;
    return _recognize(
      bytes,
      recognitionBytes is Uint8List ? recognitionBytes : null,
      path,
    );
  });
  channel.invokeMethod<void>('ready');
}

Future<Map<String, Object?>> _recognize(
  Uint8List bytes,
  Uint8List? recognitionBytes,
  String? url,
) async {
  final db = AppDatabase(openDatabaseConnection());
  final state = AppStateRepository(db);
  final store = PendingScreenshotEntryStore(state);
  final now = DateTime.now();
  final entryId = 'shot-${now.microsecondsSinceEpoch}';
  final recognitionInput = recognitionBytes ?? bytes;
  String? imagePath;

  try {
    // MediaStore 的 content:// URI 在 UI 引擎里读不了；落一份临时文件随草稿带走。
    // 落盘用原图（附件保留原图）；模型只收 Kotlin 压好的识别副本。
    imagePath = await _saveTempImage(bytes, now);
    debugPrint(
      'screenshotEntry: original=${bytes.length}B '
      'recognition=${recognitionInput.length}B '
      'mime=${VisionReceiptRecognizer.mimeOf(recognitionInput)}',
    );

    final recognizer = await systemReceiptRecognizer(
      settings: ReceiptVisionSettingsStore(state),
      keys: SecureReceiptApiKeyStore(),
    );
    if (recognizer == null) {
      const message = '视觉识别未开启，可在设置里配置 API Key';
      final pendingCount = await store.add(
        PendingScreenshotEntry(
          id: entryId,
          createdAt: now,
          imagePath: imagePath,
          error: message,
        ),
      );
      return {'ok': false, 'error': message, 'pending_count': pendingCount};
    }

    ReceiptGuess guess;
    try {
      guess = await recognizer.recognize(recognitionInput);
    } finally {
      await recognizer.close();
    }

    final usable =
        guess.hasAmount || guess.categoryName != null || guess.note != null;
    if (!usable) {
      debugPrint('screenshotEntry: empty guess');
      const message = '没认出金额，点击手动记';
      final pendingCount = await store.add(
        PendingScreenshotEntry(
          id: entryId,
          createdAt: now,
          imagePath: imagePath,
          error: message,
        ),
      );
      return {'ok': false, 'error': '没认出金额', 'pending_count': pendingCount};
    }

    final pendingCount = await store.add(
      PendingScreenshotEntry(
        id: entryId,
        createdAt: now,
        guess: guess,
        imagePath: imagePath,
      ),
    );
    return {
      'ok': true,
      'amount_cents': guess.amountCents,
      'category': guess.categoryName,
      'note': guess.note,
      'source': url,
      'pending_count': pendingCount,
    };
  } catch (error) {
    final message =
        error is ReceiptRecognitionException ? error.message : '识别失败，可以手动记';
    debugPrint('screenshotEntry: failed: $message');
    var pendingCount = 0;
    try {
      pendingCount = await store.add(
        PendingScreenshotEntry(
          id: entryId,
          createdAt: now,
          imagePath: imagePath,
          error: message,
        ),
      );
    } catch (_) {
      // 连 pending 都写不进去时，至少让通知带上真实原因
    }
    return {'ok': false, 'error': message, 'pending_count': pendingCount};
  } finally {
    await db.close();
  }
}

Future<String?> _saveTempImage(Uint8List bytes, DateTime now) async {
  try {
    final dir = await getTemporaryDirectory();
    final file =
        File('${dir.path}/screenshot_${now.microsecondsSinceEpoch}.jpg');
    await file.writeAsBytes(bytes, flush: true);
    return file.path;
  } catch (_) {
    return null;
  }
}
