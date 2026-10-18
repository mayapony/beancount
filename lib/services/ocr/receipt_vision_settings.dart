import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../../data/repositories/app_state_repository.dart';

/// 截图记账的视觉识别配置：开关、服务地址、模型名。
///
/// API Key 故意不在这里——它走系统安全存储（[ReceiptApiKeyStore]），
/// 不进 `app_state` / SQLite，也不参与序列化。
class ReceiptVisionSettings {
  const ReceiptVisionSettings({
    this.enabled = false,
    this.baseUrl = kDefaultBaseUrl,
    this.model = kDefaultModel,
  });

  /// DeepSeek 的 OpenAI 兼容端点；换厂商只改这里的默认值或设置里的地址。
  static const kDefaultBaseUrl = 'https://api.deepseek.com';

  /// DeepSeek 支持图片的模型（`deepseek-v4-pro` 不支持视觉）。
  static const kDefaultModel = 'deepseek-flash';

  /// 默认关闭：图片发到云端必须由用户显式点头。
  final bool enabled;
  final String baseUrl;
  final String model;

  /// 归一化后的地址（去掉尾部斜杠、空值回落默认），请求时直接用这个。
  String get normalizedBaseUrl => normalizeBaseUrl(baseUrl);

  String get normalizedModel => normalizeModel(model);

  bool get isDefaultEndpoint =>
      normalizedBaseUrl == kDefaultBaseUrl && normalizedModel == kDefaultModel;

  static String normalizeBaseUrl(String? raw) {
    final trimmed = (raw ?? '').trim();
    if (trimmed.isEmpty) return kDefaultBaseUrl;
    return trimmed.replaceAll(RegExp(r'/+$'), '');
  }

  static String normalizeModel(String? raw) {
    final trimmed = (raw ?? '').trim();
    return trimmed.isEmpty ? kDefaultModel : trimmed;
  }

  ReceiptVisionSettings copyWith({
    bool? enabled,
    String? baseUrl,
    String? model,
  }) {
    return ReceiptVisionSettings(
      enabled: enabled ?? this.enabled,
      baseUrl: normalizeBaseUrl(baseUrl ?? this.baseUrl),
      model: normalizeModel(model ?? this.model),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is ReceiptVisionSettings &&
      other.enabled == enabled &&
      other.normalizedBaseUrl == normalizedBaseUrl &&
      other.normalizedModel == normalizedModel;

  @override
  int get hashCode =>
      Object.hash(enabled, normalizedBaseUrl, normalizedModel);

  @override
  String toString() =>
      'ReceiptVisionSettings(enabled: $enabled, baseUrl: $normalizedBaseUrl, '
      'model: $normalizedModel)';
}

/// 配置读写：只碰 `app_state` 里的三个键，坏值一律回落默认。
class ReceiptVisionSettingsStore {
  ReceiptVisionSettingsStore(this._state);

  final AppStateRepository _state;

  static const kEnabledKey = 'vision_enabled';
  static const kBaseUrlKey = 'vision_base_url';
  static const kModelKey = 'vision_model';

  Future<ReceiptVisionSettings> load() async {
    final enabled = (await _state.read(kEnabledKey)) == 'true';
    return ReceiptVisionSettings(
      enabled: enabled,
      baseUrl: ReceiptVisionSettings.normalizeBaseUrl(
        await _state.read(kBaseUrlKey),
      ),
      model: ReceiptVisionSettings.normalizeModel(
        await _state.read(kModelKey),
      ),
    );
  }

  Future<void> save(ReceiptVisionSettings settings) async {
    await _state.write(kEnabledKey, settings.enabled ? 'true' : 'false');
    await _state.write(kBaseUrlKey, settings.normalizedBaseUrl);
    await _state.write(kModelKey, settings.normalizedModel);
  }
}

/// API Key 的存储抽象：生产用系统安全存储，测试用内存实现。
abstract class ReceiptApiKeyStore {
  Future<String?> read();

  Future<void> write(String apiKey);

  Future<void> clear();
}

/// Android Keystore / iOS Keychain；Web 用包内的加密存储实现。
class SecureReceiptApiKeyStore implements ReceiptApiKeyStore {
  SecureReceiptApiKeyStore({FlutterSecureStorage? storage})
      : _storage = storage ?? const FlutterSecureStorage();

  static const kStorageKey = 'receipt_vision_api_key';

  final FlutterSecureStorage _storage;

  @override
  Future<String?> read() async {
    final value = await _storage.read(key: kStorageKey);
    final trimmed = value?.trim();
    return (trimmed == null || trimmed.isEmpty) ? null : trimmed;
  }

  @override
  Future<void> write(String apiKey) =>
      _storage.write(key: kStorageKey, value: apiKey.trim());

  @override
  Future<void> clear() => _storage.delete(key: kStorageKey);
}

/// 测试 / 截图脚本用：只活在内存里，进程结束就没了。
class MemoryReceiptApiKeyStore implements ReceiptApiKeyStore {
  MemoryReceiptApiKeyStore([this._value]);

  String? _value;

  @override
  Future<String?> read() async {
    final trimmed = _value?.trim();
    return (trimmed == null || trimmed.isEmpty) ? null : trimmed;
  }

  @override
  Future<void> write(String apiKey) async => _value = apiKey.trim();

  @override
  Future<void> clear() async => _value = null;
}
