import '../../data/repositories/app_state_repository.dart';

/// 截屏自动记账的偏好：总开关与两个「自动新建」开关。
///
/// 全部落在 `app_state`（键值表），不新增表、不做迁移；默认全关，
/// 与「未显式开启不上传」的既有约定一致。
class ScreenshotSettings {
  const ScreenshotSettings({
    this.autoEntry = false,
    this.autoCreateCategories = false,
    this.autoTags = false,
  });

  /// 是否监听截屏并立即上传识别。
  final bool autoEntry;

  /// 识别出的分类不存在时，是否允许在保存时新建。
  final bool autoCreateCategories;

  /// 识别出的标签是否预填并在保存时创建。
  final bool autoTags;

  ScreenshotSettings copyWith({
    bool? autoEntry,
    bool? autoCreateCategories,
    bool? autoTags,
  }) {
    return ScreenshotSettings(
      autoEntry: autoEntry ?? this.autoEntry,
      autoCreateCategories: autoCreateCategories ?? this.autoCreateCategories,
      autoTags: autoTags ?? this.autoTags,
    );
  }
}

/// 读写 [ScreenshotSettings]；坏值按关闭处理，避免开着一个读不懂的开关。
class ScreenshotSettingsStore {
  ScreenshotSettingsStore(this._state);

  final AppStateRepository _state;

  static const kAutoEntryKey = 'screenshot_auto_entry_enabled';
  static const kAutoCreateCategoriesKey = 'screenshot_auto_create_categories';
  static const kAutoTagsKey = 'screenshot_auto_tags';

  Future<ScreenshotSettings> load() async {
    return ScreenshotSettings(
      autoEntry: await _readBool(kAutoEntryKey),
      autoCreateCategories: await _readBool(kAutoCreateCategoriesKey),
      autoTags: await _readBool(kAutoTagsKey),
    );
  }

  Future<void> save(ScreenshotSettings settings) async {
    await _state.write(kAutoEntryKey, settings.autoEntry ? 'true' : 'false');
    await _state.write(
      kAutoCreateCategoriesKey,
      settings.autoCreateCategories ? 'true' : 'false',
    );
    await _state.write(kAutoTagsKey, settings.autoTags ? 'true' : 'false');
  }

  Future<bool> _readBool(String key) async => (await _state.read(key)) == 'true';
}
