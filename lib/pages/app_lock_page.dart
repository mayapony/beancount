import 'package:flutter/material.dart';

import '../data/repositories/lock_repository.dart';
import '../services/security/pin_hasher.dart';
import '../theme/tokens.dart';
import '../widgets/common.dart';

/// 设置 →「应用锁」：开启 / 修改 / 关闭。三个动作都要先证明是本人。
class AppLockPage extends StatefulWidget {
  const AppLockPage({super.key, required this.repository});

  final LockRepository repository;

  @override
  State<AppLockPage> createState() => _AppLockPageState();
}

class _AppLockPageState extends State<AppLockPage> {
  bool _enabled = false;
  bool _loading = true;
  String? _message;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    final enabled = await widget.repository.isEnabled();
    if (!mounted) return;
    setState(() {
      _enabled = enabled;
      _loading = false;
    });
  }

  Future<String?> _askPin(String title, {String hint = ''}) {
    return showDialog<String>(
      context: context,
      builder: (_) => _PinDialog(title: title, hint: hint),
    );
  }

  Future<void> _enable() async {
    final first = await _askPin('设置 PIN', hint: '4–$kPinMaxLength 位数字');
    if (first == null || !mounted) return;
    if (!isValidPin(first)) {
      setState(() => _message = 'PIN 必须是 $kPinMinLength–$kPinMaxLength 位数字');
      return;
    }
    final second = await _askPin('再输入一次');
    if (second == null || !mounted) return;
    if (first != second) {
      setState(() => _message = '两次输入不一致，请重试');
      return;
    }
    await widget.repository.setPin(first);
    if (!mounted) return;
    setState(() => _message = '已开启应用锁');
    await _reload();
  }

  Future<bool> _confirmCurrentPin() async {
    final pin = await _askPin('输入当前 PIN');
    if (pin == null || !mounted) return false;
    final ok = await widget.repository.verify(pin);
    if (!mounted) return false;
    if (!ok) {
      setState(() => _message = 'PIN 不正确');
      return false;
    }
    return true;
  }

  Future<void> _change() async {
    if (!await _confirmCurrentPin() || !mounted) return;
    final first = await _askPin('设置新 PIN');
    if (first == null || !mounted) return;
    if (!isValidPin(first)) {
      setState(() => _message = 'PIN 必须是 $kPinMinLength–$kPinMaxLength 位数字');
      return;
    }
    final second = await _askPin('再输入一次');
    if (second == null || !mounted) return;
    if (first != second) {
      setState(() => _message = '两次输入不一致，请重试');
      return;
    }
    await widget.repository.setPin(first);
    if (!mounted) return;
    setState(() => _message = 'PIN 已更新');
    await _reload();
  }

  Future<void> _disable() async {
    if (!await _confirmCurrentPin() || !mounted) return;
    await widget.repository.disable();
    if (!mounted) return;
    setState(() => _message = '已关闭应用锁');
    await _reload();
  }

  @override
  Widget build(BuildContext context) {
    final palette = BeanPalette.of(context);

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
          '应用锁',
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
                  child: Column(
                    children: [
                      _Tile(
                        title: _enabled ? '已开启' : '已关闭',
                        subtitle: _enabled
                            ? '打开 App 需要输入 PIN'
                            : '开启后，打开 App 需要输入 PIN',
                        trailing: _enabled ? '开启' : '关闭',
                      ),
                      if (!_enabled)
                        _Action(
                          label: '开启应用锁',
                          onTap: _enable,
                        )
                      else ...[
                        Divider(
                          height: BeanSpace.hairline,
                          thickness: BeanSpace.hairline,
                          indent: 16,
                          color: palette.border,
                        ),
                        _Action(label: '修改 PIN', onTap: _change),
                        Divider(
                          height: BeanSpace.hairline,
                          thickness: BeanSpace.hairline,
                          indent: 16,
                          color: palette.border,
                        ),
                        _Action(
                          label: '关闭应用锁',
                          danger: true,
                          onTap: _disable,
                        ),
                      ],
                    ],
                  ),
                ),
                if (_message != null) ...[
                  const SizedBox(height: 12),
                  Text(
                    _message!,
                    style: TextStyle(fontSize: 13, color: palette.textSecondary),
                  ),
                ],
                const SizedBox(height: BeanSpace.section),
                Text(
                  'PIN 只在你自己的设备上用加盐摘要保存，不会上传。忘记 PIN 只能重装 App（本地数据会丢失）。',
                  style: TextStyle(fontSize: 12, color: palette.textSecondary),
                ),
                const SizedBox(height: 8),
                Text(
                  '生物识别（指纹/面容）还没有接入，正在 Backlog 里排队。',
                  style: TextStyle(fontSize: 12, color: palette.textSecondary),
                ),
              ],
            ),
    );
  }
}

class _Tile extends StatelessWidget {
  const _Tile({
    required this.title,
    required this.subtitle,
    required this.trailing,
  });

  final String title;
  final String subtitle;
  final String trailing;

  @override
  Widget build(BuildContext context) {
    final palette = BeanPalette.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: TextStyle(fontSize: 12, color: palette.textSecondary),
                ),
              ],
            ),
          ),
          Text(
            trailing,
            style: TextStyle(fontSize: 13, color: palette.textSecondary),
          ),
        ],
      ),
    );
  }
}

class _Action extends StatelessWidget {
  const _Action({
    required this.label,
    required this.onTap,
    this.danger = false,
  });

  final String label;
  final VoidCallback onTap;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final palette = BeanPalette.of(context);
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            Text(
              label,
              style: TextStyle(
                fontSize: 15,
                color: danger ? palette.alert : null,
              ),
            ),
            const Spacer(),
            Icon(
              Icons.chevron_right_rounded,
              size: 20,
              color: palette.textSecondary,
            ),
          ],
        ),
      ),
    );
  }
}

/// 输 PIN 的弹窗：数字、遮挡显示、4–6 位。
class _PinDialog extends StatefulWidget {
  const _PinDialog({required this.title, this.hint = ''});

  final String title;
  final String hint;

  @override
  State<_PinDialog> createState() => _PinDialogState();
}

class _PinDialogState extends State<_PinDialog> {
  final TextEditingController _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(
        widget.title,
        style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
      ),
      content: TextField(
        controller: _controller,
        autofocus: true,
        obscureText: true,
        keyboardType: TextInputType.number,
        maxLength: kPinMaxLength,
        decoration: InputDecoration(
          hintText: widget.hint.isEmpty ? '4–6 位数字' : widget.hint,
          counterText: '',
          isDense: true,
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(_controller.text.trim()),
          child: const Text('确定'),
        ),
      ],
    );
  }
}
