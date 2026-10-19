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
import 'services/screenshot/auto_entry.dart';
import 'services/screenshot/pending_entry.dart';
import 'services/screenshot/screenshot_settings.dart';

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

  try {
    final settings = await ScreenshotSettingsStore(state).load();
    if (!settings.autoEntry) {
      return {'ok': false, 'error': '截屏自动识别已关闭'};
    }

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
      final pendingCount = await _addPending(
        store: store,
        id: entryId,
        now: now,
        bytes: bytes,
        error: message,
      );
      return {'ok': false, 'error': message, 'pending_count': pendingCount};
    }

    ReceiptGuess guess;
    try {
      guess = await recognizer.recognize(recognitionInput);
    } finally {
      await recognizer.close();
    }

    if (guess.hasAmount) {
      // 识别出金额就直接落库：原图随交易保存，不再让用户打开面板确认。
      try {
        final saved = await AutoScreenshotSaver(db: db).save(
          guess: guess,
          imageBytes: bytes,
          fileName: 'screenshot_${now.microsecondsSinceEpoch}.jpg',
          autoTags: settings.autoTags,
          now: now,
        );
        final pendingCount = await store.count();
        debugPrint(
          'screenshotEntry: auto saved amount=${saved.amountCents} '
          'duplicate=${saved.duplicate} category=${saved.categoryName} '
          'account=${saved.accountName}',
        );
        return {
          'ok': true,
          'auto_saved': true,
          'duplicate': saved.duplicate,
          'amount_cents': saved.amountCents,
          'category': saved.categoryName,
          'account': saved.accountName,
          'source': url,
          'pending_count': pendingCount,
        };
      } catch (error) {
        debugPrint('screenshotEntry: auto save failed: $error');
        final pendingCount = await _addPending(
          store: store,
          id: entryId,
          now: now,
          bytes: bytes,
          guess: guess,
        );
        return {
          'ok': false,
          'error': '自动记账失败，点击确认',
          'pending_count': pendingCount,
        };
      }
    }

    // 没金额不能自动记：保留分类/商家预填，让用户只补金额；全空则只提示。
    final hasFields =
        guess.categoryName != null || (guess.note ?? '').trim().isNotEmpty;
    final pendingCount = await _addPending(
      store: store,
      id: entryId,
      now: now,
      bytes: bytes,
      guess: hasFields ? guess : null,
      error: hasFields ? null : '没认出金额，点击手动记',
    );
    return {'ok': false, 'error': '没认出金额', 'pending_count': pendingCount};
  } catch (error) {
    final message =
        error is ReceiptRecognitionException ? error.message : '识别失败，可以手动记';
    // 带上原始异常：只在界面上说「识别失败」会把根因吃掉。
    debugPrint('screenshotEntry: failed: $message ($error)');
    var pendingCount = 0;
    try {
      pendingCount = await _addPending(
        store: store,
        id: entryId,
        now: now,
        bytes: bytes,
        error: message,
      );
    } catch (_) {
      // 连 pending 都写不进去时，至少让通知带上真实原因
    }
    return {'ok': false, 'error': message, 'pending_count': pendingCount};
  } finally {
    await db.close();
  }
}

Future<int> _addPending({
  required PendingScreenshotEntryStore store,
  required String id,
  required DateTime now,
  required Uint8List bytes,
  ReceiptGuess? guess,
  String? error,
}) async {
  final imagePath = await _saveTempImage(bytes, now);
  return store.add(
    PendingScreenshotEntry(
      id: id,
      createdAt: now,
      guess: guess,
      imagePath: imagePath,
      error: error,
    ),
  );
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
