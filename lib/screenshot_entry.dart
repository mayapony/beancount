import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:path_provider/path_provider.dart';

import 'data/db/app_database.dart';
import 'data/db/connection.dart';
import 'data/repositories/app_state_repository.dart';
import 'services/capture/capture_candidate.dart';
import 'services/capture/capture_evidence.dart';
import 'services/capture/capture_rule_generator_cloud.dart';
import 'services/capture/capture_rule_learner.dart';
import 'services/capture/capture_surface.dart';
import 'services/capture/capture_tree.dart';
import 'services/ocr/receipt_guess.dart';
import 'services/ocr/receipt_recognizer_factory.dart';
import 'services/ocr/receipt_recognizer_vision.dart';
import 'services/ocr/receipt_vision_settings.dart';
import 'services/screenshot/auto_entry.dart';
import 'services/screenshot/pending_entry.dart';
import 'services/screenshot/screenshot_settings.dart';

/// 后台识别入口：由 `ScreenshotService` 里的 headless FlutterEngine 运行。
///
/// 收到截图字节 → 复用现有识别器 → 把结果写进 `app_state`；识别出金额时直接
/// 入账，并异步留证（包名/指纹/树快照）→ 云端生成规则。不碰 UI；通知由
/// Kotlin 侧根据返回值发。
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
    final result = await _recognize(
      bytes,
      recognitionBytes is Uint8List ? recognitionBytes : null,
      path,
    );
    // 直接入账成功后异步留证 + 学规则，不阻塞识别结果与通知返回。
    if (result['ok'] == true && result['auto_saved'] == true) {
      final amount = result['amount_cents'];
      if (amount is int) {
        unawaited(_learnFromScreenshot(channel, amountCents: amount));
      }
    }
    return result;
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

/// 截图兜底留证 + 规则学习：从原生环形缓冲取回最近一帧树快照，留证后交给
/// [CaptureRuleLearner] 生成规则。树读不出则标记「截图优先」，不反复生成。
Future<void> _learnFromScreenshot(
  MethodChannel channel, {
  required int amountCents,
}) async {
  final db = AppDatabase(openDatabaseConnection());
  try {
    // 截图后 MIUI 会弹截图工具栏（系统悬浮窗），无障碍现读时可能还挡在前面，
    // 所以带重试：直到读到「非系统窗口」的树为止。
    final snapshot = await _fetchCurrentTree(channel);
    final package = snapshot?['package'];
    final dump = snapshot?['dump'];
    if (package == null || dump == null) {
      await _log(channel, 'learn: no snapshot (tree unreadable/system window)');
      return;
    }

    // 把当前包记进「已认识」，之后对它持续抓树 / 监听通知。
    await channel.invokeMethod<void>('addKnown', {'package': package});

    final tree = dumpToTree(dump);
    final fingerprint = surfaceFingerprintOf(tree);
    final state = AppStateRepository(db);
    final surfaces = CaptureSurfaceStore(state);

    if (tree.flattenedText.trim().isEmpty) {
      await _log(channel, 'learn: tree empty → mark screenshot-first pkg=$package');
      await surfaces.mark(package, fingerprint);
      return;
    }

    await _log(channel, 'learn: store evidence pkg=$package fp=$fingerprint amount=$amountCents');
    await CaptureEvidenceStore(state).add(
      CaptureEvidence(
        id: 'evt-${DateTime.now().microsecondsSinceEpoch}',
        packageName: package,
        dump: dump,
        amountCents: amountCents,
        direction: CaptureDirection.expense,
        surfaceFingerprint: fingerprint,
        createdAt: DateTime.now(),
      ),
    );

    final generator = await systemCaptureRuleGenerator(
      settings: ReceiptVisionSettingsStore(state),
      keys: SecureReceiptApiKeyStore(),
    );
    if (generator == null) {
      await _log(channel, 'learn: generator null (vision not configured)');
      return;
    }
    try {
      final learner = CaptureRuleLearner(
        db: db,
        generator: generator,
        isConfigured: () async => true,
        log: (message) => _log(channel, message),
      );
      await learner.learnAll();
    } finally {
      generator.close();
    }
  } catch (error) {
    await _log(channel, 'learn: failed $error');
    debugPrint('screenshotEntry: rule learning failed: $error');
  } finally {
    await db.close();
  }
}

/// 现读当前前台应用树：最多重试 6 次、每次等 1 秒，跳过系统悬浮窗（截图工具栏）。
Future<Map<String, String>?> _fetchCurrentTree(MethodChannel channel) async {
  for (var attempt = 0; attempt < 6; attempt++) {
    final snapshot = await channel.invokeMapMethod<String, String>('lastTreeSnapshot');
    final package = snapshot?['package'];
    final dump = snapshot?['dump'];
    if (package != null && dump != null && dump.isNotEmpty) {
      return snapshot;
    }
    await Future<void>.delayed(const Duration(seconds: 1));
  }
  return null;
}

Future<void> _log(MethodChannel channel, String message) async {
  try {
    await channel.invokeMethod<void>('log', {'message': message});
  } catch (_) {
    // 日志失败不打断主流程。
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
