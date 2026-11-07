import 'capture_diagnostics.dart';

/// 没有文件系统（Web）时没有 JSONL 落点，只记页面环形。
CaptureDiagSink? defaultCaptureDiagSink() => null;