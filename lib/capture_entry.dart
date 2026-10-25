import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

/// 后台捕获引擎入口：由 [CaptureService] 里的 headless FlutterEngine 运行。
///
/// 只做一件事——接住无障碍 / 通知转来的事件。规则匹配 → 候选去重 → 入账的
/// 完整管线在后续任务接到这里；这里先留空，保证通道能通、事件能收到。
@pragma('vm:entry-point')
void captureEntry() {
  WidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('com.jindou.bean_count/capture');
  channel.setMethodCallHandler((call) async {
    switch (call.method) {
      case 'treeCaptured':
      case 'notificationCaptured':
        // 占位：完整管线在 tasks 6.x 接入。
        return null;
      default:
        return null;
    }
  });
  channel.invokeMethod<void>('ready');
}
