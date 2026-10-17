/// 条件导入的门面：Web 走 wasm，其余平台走 sqlite3 原生实现。
///
/// 调用方统一 `import 'connection.dart'`，不需要知道平台差异。
/// 为什么必须分开：`drift/native.dart` 依赖 `dart:ffi`，在 Web 上是**编译期**失败，
/// 靠 `kIsWeb` 分支绕不过去。
library;

export 'connection_io.dart'
    if (dart.library.js_interop) 'connection_web.dart';
