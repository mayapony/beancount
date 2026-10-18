import '../db/app_database.dart';

/// 上次记账的选择（分类 / 账户 / 收支类型）。
class LastEntrySelection {
  const LastEntrySelection({
    this.categoryId,
    this.accountId,
    this.isIncome = false,
  });

  final String? categoryId;
  final String? accountId;
  final bool isIncome;
}

/// 轻量键值仓储：只存"下次打开面板要继承什么"这类偏好。
///
/// 不建独立表，用 `app_state(key, value)`——这类数据是 UI 记忆，不是账本事实。
class AppStateRepository {
  AppStateRepository(this._db);

  final AppDatabase _db;

  static const kLastCategoryId = 'last_category_id';
  static const kLastAccountId = 'last_account_id';
  static const kLastIsIncome = 'last_is_income';

  Future<String?> read(String key) async {
    final row = await (_db.select(_db.appState)
          ..where((t) => t.key.equals(key)))
        .getSingleOrNull();
    return row?.value;
  }

  Future<void> write(String key, String value) async {
    await _db.into(_db.appState).insertOnConflictUpdate(
          AppStateCompanion.insert(key: key, value: value),
        );
  }

  Future<void> remove(String key) async {
    await (_db.delete(_db.appState)..where((t) => t.key.equals(key))).go();
  }

  /// 删除单个 key，返回是否真的删掉了。
  /// 多个 isolate/引擎同时消费队列时，用它做「谁删到谁拿走」的原子抢占。
  Future<bool> removeIfPresent(String key) async {
    final deleted =
        await (_db.delete(_db.appState)..where((t) => t.key.equals(key))).go();
    return deleted > 0;
  }

  /// 读取以 [prefix] 开头的键值对（待确认截图队列用）。
  ///
  /// app_state 只有几十个键，直接全读后在 Dart 里按前缀过滤；
  /// 比依赖 drift 的 like 扩展更稳。
  Future<List<MapEntry<String, String>>> readStartingWith(String prefix) async {
    final rows = await _db.select(_db.appState).get();
    return [
      for (final row in rows)
        if (row.key.startsWith(prefix)) MapEntry(row.key, row.value),
    ];
  }

  Future<LastEntrySelection> lastSelection() async {
    final categoryId = await read(kLastCategoryId);
    final accountId = await read(kLastAccountId);
    final isIncome = (await read(kLastIsIncome)) == 'true';
    return LastEntrySelection(
      categoryId: categoryId,
      accountId: accountId,
      isIncome: isIncome,
    );
  }

  Future<void> saveSelection(LastEntrySelection selection) async {
    if (selection.categoryId != null) {
      await write(kLastCategoryId, selection.categoryId!);
    }
    if (selection.accountId != null) {
      await write(kLastAccountId, selection.accountId!);
    }
    await write(kLastIsIncome, selection.isIncome ? 'true' : 'false');
  }
}
