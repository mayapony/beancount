import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

import '../services/ocr/receipt_vision_settings.dart';
import '../theme/tokens.dart';
import '../widgets/common.dart';

/// 设置 →「截图记账」：视觉模型开关、API Key、服务地址与模型。
///
/// 只有「开关打开 + 已保存 Key」才会真正识别；Key 只进系统安全存储，
/// 页面从不回显它，只显示「已保存」。
class VisionSettingsPage extends StatefulWidget {
  const VisionSettingsPage({
    super.key,
    required this.settings,
    required this.keys,
  });

  final ReceiptVisionSettingsStore settings;
  final ReceiptApiKeyStore keys;

  @override
  State<VisionSettingsPage> createState() => _VisionSettingsPageState();
}

class _VisionSettingsPageState extends State<VisionSettingsPage> {
  final _keyController = TextEditingController();
  final _baseUrlController = TextEditingController();
  final _modelController = TextEditingController();

  ReceiptVisionSettings _settings = const ReceiptVisionSettings();
  bool _hasKey = false;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  @override
  void dispose() {
    _keyController.dispose();
    _baseUrlController.dispose();
    _modelController.dispose();
    super.dispose();
  }

  Future<void> _reload() async {
    final settings = await widget.settings.load();
    final key = await widget.keys.read();
    if (!mounted) return;
    setState(() {
      _settings = settings;
      _hasKey = key != null;
      _baseUrlController.text = settings.normalizedBaseUrl;
      _modelController.text = settings.normalizedModel;
      _loading = false;
    });
  }

  /// 开启但没 Key 时明确告诉用户「还不生效」，而不是假装开着。
  bool get _enabledButUnusable => _settings.enabled && !_hasKey;

  /// 动作反馈走 SnackBar：不和表单抢位置，也不需要滚到底才看得见。
  void _notify(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _setEnabled(bool enabled) async {
    final next = _settings.copyWith(enabled: enabled);
    await widget.settings.save(next);
    if (!mounted) return;
    setState(() => _settings = next);
    _notify(enabled
        ? (_hasKey
            ? '已开启：添加图片会发送给 ${Uri.tryParse(next.normalizedBaseUrl)?.host ?? next.normalizedBaseUrl}'
            : '还没保存 API Key，识别不会生效')
        : '已关闭：图片不会离开设备');
  }

  Future<void> _saveKey() async {
    final key = _keyController.text.trim();
    if (key.isEmpty) {
      _notify('先粘贴 API Key');
      return;
    }
    await widget.keys.write(key);
    if (!mounted) return;
    setState(() {
      _keyController.clear();
      _hasKey = true;
    });
    _notify(
      _settings.enabled ? 'API Key 已保存，识别已生效' : 'API Key 已保存，记得打开开关',
    );
  }

  Future<void> _clearKey() async {
    await widget.keys.clear();
    final next = _settings.copyWith(enabled: false);
    await widget.settings.save(next);
    if (!mounted) return;
    setState(() {
      _hasKey = false;
      _settings = next;
    });
    _notify('已清除 API Key，识别已关闭');
  }

  Future<void> _saveAdvanced() async {
    final next = _settings.copyWith(
      baseUrl: _baseUrlController.text,
      model: _modelController.text,
    );
    await widget.settings.save(next);
    if (!mounted) return;
    setState(() {
      _settings = next;
      _baseUrlController.text = next.normalizedBaseUrl;
      _modelController.text = next.normalizedModel;
    });
    _notify('服务地址与模型已保存');
  }

  Future<void> _resetAdvanced() async {
    final next = ReceiptVisionSettings(
      enabled: _settings.enabled,
      baseUrl: ReceiptVisionSettings.kDefaultBaseUrl,
      model: ReceiptVisionSettings.kDefaultModel,
    );
    await widget.settings.save(next);
    if (!mounted) return;
    setState(() {
      _settings = next;
      _baseUrlController.text = next.normalizedBaseUrl;
      _modelController.text = next.normalizedModel;
    });
    _notify('已恢复默认（DeepSeek）');
  }

  @override
  Widget build(BuildContext context) {
    final palette = BeanPalette.of(context);
    final host = Uri.tryParse(_settings.normalizedBaseUrl)?.host ??
        _settings.normalizedBaseUrl;

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        leading: IconButton(
          tooltip: '返回',
          icon: const Icon(Icons.chevron_left_rounded, size: 28),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: const Text(
          '截图记账',
          style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
        ),
        centerTitle: true,
      ),
      body: _loading
          ? const SizedBox.shrink()
          : ListView(
              padding: const EdgeInsets.fromLTRB(
                BeanSpace.page,
                8,
                BeanSpace.page,
                40,
              ),
              children: [
                BeanCard(
                  padding: EdgeInsets.zero,
                  child: SwitchListTile.adaptive(
                    key: const ValueKey('vision-switch'),
                    value: _settings.enabled,
                    onChanged: _setEnabled,
                    contentPadding:
                        const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                    title: const Text(
                      '视觉识别',
                      style: TextStyle(fontSize: 17, height: 1.25),
                    ),
                    subtitle: Text(
                      _settings.enabled
                          ? '添加图片后发送给 $host（${_settings.normalizedModel}）'
                          : '关闭时不做识别，图片不会离开设备',
                      style: TextStyle(
                        fontSize: 13,
                        height: 1.2,
                        color: palette.textSecondary,
                      ),
                    ),
                    secondary: Container(
                      width: 29,
                      height: 29,
                      decoration: BoxDecoration(
                        color: BeanColors.beanGreen,
                        borderRadius: BorderRadius.circular(7),
                      ),
                      child: const Icon(
                        Icons.auto_awesome_rounded,
                        size: 18,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
                if (kIsWeb) ...[
                  const SizedBox(height: 10),
                  Text(
                    '网页版不支持识别（浏览器直连第三方接口会被 CORS 拦），设置会保留到手机端。',
                    style: TextStyle(
                      fontSize: 13,
                      color: palette.textSecondary,
                    ),
                  ),
                ] else if (_enabledButUnusable) ...[
                  const SizedBox(height: 10),
                  Text(
                    '已开启但还没有 API Key：识别不会生效。',
                    style: TextStyle(
                      fontSize: 13,
                      color: BeanColors.alertRed,
                    ),
                  ),
                ],
                const SizedBox(height: BeanSpace.section),
                const SectionTitle('API Key'),
                BeanCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      TextField(
                        key: const ValueKey('vision-key-field'),
                        controller: _keyController,
                        obscureText: true,
                        autocorrect: false,
                        enableSuggestions: false,
                        decoration: InputDecoration(
                          hintText: _hasKey ? '已保存（输入新的可替换）' : '粘贴 API Key',
                          border: const OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          FilledButton(
                            key: const ValueKey('vision-key-save'),
                            onPressed: _saveKey,
                            child: const Text('保存 Key'),
                          ),
                          if (_hasKey) ...[
                            const SizedBox(width: 10),
                            TextButton(
                              key: const ValueKey('vision-key-clear'),
                              onPressed: _clearKey,
                              child: const Text('清除'),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Key 只存在系统安全存储（Android Keystore / iOS Keychain），'
                        '不进数据库、不进日志。',
                        style: TextStyle(
                          fontSize: 12,
                          height: 1.4,
                          color: palette.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: BeanSpace.section),
                const SectionTitle('高级'),
                BeanCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      TextField(
                        key: const ValueKey('vision-base-url'),
                        controller: _baseUrlController,
                        keyboardType: TextInputType.url,
                        autocorrect: false,
                        decoration: const InputDecoration(
                          labelText: '服务地址',
                          helperText: 'OpenAI 兼容端点，默认 DeepSeek',
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 14),
                      TextField(
                        key: const ValueKey('vision-model'),
                        controller: _modelController,
                        autocorrect: false,
                        decoration: const InputDecoration(
                          labelText: '模型',
                          helperText: '需要支持图片输入',
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          FilledButton(
                            key: const ValueKey('vision-advanced-save'),
                            onPressed: _saveAdvanced,
                            child: const Text('保存'),
                          ),
                          const SizedBox(width: 10),
                          TextButton(
                            key: const ValueKey('vision-advanced-reset'),
                            onPressed: _resetAdvanced,
                            child: const Text('恢复默认'),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: BeanSpace.section),
                Text(
                  '识别只把图片换成文字，金额、分类、日期仍由本地规则解析，'
                  '入账前一定让你确认。识别失败不影响保存。',
                  style: TextStyle(
                    fontSize: 12,
                    height: 1.5,
                    color: palette.textSecondary,
                  ),
                ),
              ],
            ),
    );
  }
}
