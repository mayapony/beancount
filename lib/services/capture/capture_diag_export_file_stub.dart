/// 非 io 平台（Web）没有可写的私有目录：导出只走系统保存对话框。
Future<String?> writeCaptureDiagExport(String text, {DateTime? at}) async => null;
