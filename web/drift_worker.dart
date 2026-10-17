import 'package:drift/wasm.dart';

/// Web worker：把 sqlite3 的 wasm 放进后台线程，避免长查询卡住 UI。
///
/// 需要编译成 JS 才能被 `WasmDatabase.open` 引用：
///   dart compile js -O2 web/drift_worker.dart -o web/drift_worker.dart.js
void main() {
  WasmDatabase.workerMainForOpen();
}
