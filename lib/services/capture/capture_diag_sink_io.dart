import 'capture_diag_log.dart';
import 'capture_diagnostics.dart';

/// 默认的 JSONL 落点：真机上把每条记录追加到 `diag/events.log`。
CaptureDiagSink? defaultCaptureDiagSink() {
  return (line) async => (await openCaptureDiagLog())?.append(line);
}
