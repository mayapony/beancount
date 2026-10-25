import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import 'data/db/app_database.dart';
import 'data/db/connection.dart';
import 'services/capture/capture_runtime.dart';

/// 后台捕获引擎入口：由 [CaptureService] 里的 headless FlutterEngine 运行。
///
/// 接住无障碍 / 通知转来的事件 → 规则匹配 → 候选去重 → 入账 → 通知。
/// 业务逻辑全在 [CaptureRuntime]，这里只做通道与引擎的接线。
@pragma('vm:entry-point')
void captureEntry() {
  WidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('com.jindou.bean_count/capture');
  final db = AppDatabase(openDatabaseConnection());
  final runtime = CaptureRuntime(db: db, notifier: _ChannelNotifier(channel));
  channel.setMethodCallHandler((call) async {
    final args = call.arguments;
    switch (call.method) {
      case 'treeCaptured':
        if (args is Map) {
          final package = args['package'];
          final dump = args['dump'];
          if (package is String && dump is String) {
            await runtime.onTreeCaptured(packageName: package, dump: dump);
          }
        }
        return null;
      case 'notificationCaptured':
        if (args is Map) {
          final package = args['package'];
          final text = args['text'];
          if (package is String && text is String) {
            await runtime.onNotificationCaptured(
              packageName: package,
              text: text,
            );
          }
        }
        return null;
      default:
        return null;
    }
  });
  channel.invokeMethod<void>('ready');
}

/// headless 引擎里发「已记账」通知：经同一通道回到原生侧。
class _ChannelNotifier implements CaptureNotifier {
  _ChannelNotifier(this._channel);

  final MethodChannel _channel;

  @override
  Future<void> notifyEntry({
    required int amountCents,
    required String note,
  }) async {
    try {
      await _channel.invokeMethod<void>('notifyEntry', {
        'amount_cents': amountCents,
        'note': note,
      });
    } catch (_) {
      // 通知发不出去不影响入账本身。
    }
  }
}
