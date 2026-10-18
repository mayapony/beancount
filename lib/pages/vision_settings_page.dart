import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

import '../services/ocr/receipt_vision_settings.dart';
import '../services/ocr/vision_probe.dart';
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
    this.probe,
  });

  final ReceiptVisionSettingsStore settings;
  final ReceiptApiKeyStore keys;

  /// 测试入口；测试里注入假实现，线上走 [probeVision]。
  final VisionProbeRunner? probe;

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
  bool _probing = false;
  String? _probeMessage;
  bool _probeOk = false;

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

  Future<void> _saveAll() async {
    final key = _keyController.text.trim();
    if (key.isNotEmpty) {
      await widget.keys.write(key);
      if (!mounted) return;
      setState(() {
        _keyController.clear();
        _hasKey = true;
      });
    }

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

    if (key.isNotEmpty) {
      _notify(
        _settings.enabled ? '设置已保存，识别已生效' : '设置已保存，记得打开开关',
      );
    } else if (_settings.enabled && !_hasKey) {
      _notify('设置已保存；还没有 API Key，识别不会生效');
    } else {
      _notify('设置已保存');
    }
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

  /// 用当前表单里的地址/模型/Key（不保存）发一张合成小票，验证链路通不通。
  Future<void> _testVision() async {
    if (_probing) return;
    final typed = _keyController.text.trim();
    final apiKey = typed.isNotEmpty ? typed : await widget.keys.read();
    if (!mounted) return;
    if (apiKey == null || apiKey.trim().isEmpty) {
      setState(() {
        _probeOk = false;
        _probeMessage = '先填一个 API Key 再测试';
      });
      return;
    }

    final baseUrl =
        ReceiptVisionSettings.normalizeBaseUrl(_baseUrlController.text);
    final model = ReceiptVisionSettings.normalizeModel(_modelController.text);
    setState(() {
      _probing = true;
      _probeMessage = null;
    });

    final runner = widget.probe ?? probeVision;
    final result = await runner(
      baseUrl: baseUrl,
      model: model,
      apiKey: apiKey,
    );
    if (!mounted) return;
    final cents = result.guess?.amountCents;
    setState(() {
      _probing = false;
      _probeOk = result.ok;
      _probeMessage = result.ok
          ? '识别正常：测试小票 ¥${((cents ?? 0) / 100).toStringAsFixed(2)}'
          : '测试失败：${result.message ?? '未知原因'}';
    });
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
                      if (_hasKey)
                        Align(
                          alignment: Alignment.centerLeft,
                          child: TextButton(
                            key: const ValueKey('vision-key-clear'),
                            onPressed: _clearKey,
                            style: TextButton.styleFrom(
                              padding: EdgeInsets.zero,
                              minimumSize: const Size(0, 32),
                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            ),
                            child: const Text('清除已保存的 Key'),
                          ),
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
                      const SizedBox(height: 12),
                      // Web 直连第三方端点会被 CORS 拦，不提供假承诺
                      if (!kIsWeb)
                        OutlinedButton.icon(
                          key: const ValueKey('vision-probe'),
                          onPressed: _probing ? null : _testVision,
                          icon: _probing
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Icon(
                                  Icons.wifi_tethering_rounded,
                                  size: 18,
                                ),
                          label: Text(_probing ? '测试中…' : '测试识别'),
                        ),
                      if (_probeMessage != null) ...[
                        const SizedBox(height: 8),
                        Text(
                          _probeMessage!,
                          key: const ValueKey('vision-probe-result'),
                          style: TextStyle(
                            fontSize: 12,
                            height: 1.4,
                            color: _probeOk
                                ? BeanColors.beanGreen
                                : BeanColors.alertRed,
                          ),
                        ),
                      ],
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
                      Align(
                        alignment: Alignment.centerLeft,
                        child: TextButton(
                          key: const ValueKey('vision-advanced-reset'),
                          onPressed: _resetAdvanced,
                          style: TextButton.styleFrom(
                            padding: EdgeInsets.zero,
                            minimumSize: const Size(0, 32),
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          ),
                          child: const Text('恢复默认'),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: BeanSpace.section),
                Text(
                  '识别直接给出金额、商家、分类与时间；入账前一定让你确认，'
                  '认错了可以当场改。识别失败不影响保存。',
                  style: TextStyle(
                    fontSize: 12,
                    height: 1.5,
                    color: palette.textSecondary,
                  ),
                ),
              ],
            ),
      bottomNavigationBar: _loading
          ? null
          : SafeArea(
              minimum: const EdgeInsets.fromLTRB(
                BeanSpace.page,
                8,
                BeanSpace.page,
                16,
              ),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton(
                  key: const ValueKey('vision-save'),
                  onPressed: _saveAll,
                  child: const Text('保存设置'),
                ),
              ),
            ),
    );
  }
}
