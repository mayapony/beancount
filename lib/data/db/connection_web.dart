import 'package:drift/drift.dart';
import 'package:drift/wasm.dart';

/// Web 端的数据库：`drift/wasm.dart` + `web/sqlite3.wasm` + `web/drift_worker.dart.js`。
///
/// 为什么不能直接复用移动端实现：`drift/native.dart` 依赖 `dart:ffi`，
/// 在 Web 上**编译期**就会失败（不是运行时报错），所以必须用条件导入分开。
///
/// 存储位置由 drift 探测：有 IndexedDB + SharedWorker 就落到 IndexedDB（刷新还在），
/// 否则降级成内存库（刷新即丢）。Web 只当设计预览，不作为数据可信环境。
QueryExecutor openDatabaseConnection() {
  return LazyDatabase(() async {
    final result = await WasmDatabase.open(
      databaseName: 'bean_count',
      sqlite3Uri: Uri.parse('sqlite3.wasm'),
      driftWorkerUri: Uri.parse('drift_worker.dart.js'),
    );
    return result.resolvedExecutor;
  });
}

/// Web 上没有"独立的内存库"概念，直接用同一个 wasm 实现即可。
QueryExecutor openInMemoryConnection() => openDatabaseConnection();
