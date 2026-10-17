import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// 数据库文件名（放在应用文档目录，随卸载删除）。
const kDatabaseFileName = 'bean_count.sqlite';

/// 打开本地数据库：`<appDocs>/bean_count.sqlite`，后台 isolate 打开（不阻塞首帧）。
QueryExecutor openDatabaseConnection() {
  return LazyDatabase(() async {
    final dir = await getApplicationDocumentsDirectory();
    final file = File(p.join(dir.path, kDatabaseFileName));
    return NativeDatabase.createInBackground(file);
  });
}

/// 内存库：单测用，关闭即丢。
QueryExecutor openInMemoryConnection() => NativeDatabase.memory();
