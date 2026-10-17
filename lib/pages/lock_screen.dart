import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/tokens.dart';

/// 锁屏：圆点 + 数字键盘。
///
/// 输满已设置的位数就自动校验；连续 5 次失败锁 30 秒（倒计时期间键盘禁用）。
class LockScreen extends StatefulWidget {
  const LockScreen({
    super.key,
    required this.length,
    required this.onVerify,
    required this.onUnlocked,
    this.now,
    this.maxAttempts = 5,
    this.lockDuration = const Duration(seconds: 30),
  });

  /// PIN 位数（画几个圆点）。
  final int length;

  /// 校验回调：true 表示 PIN 正确。
  final Future<bool> Function(String pin) onVerify;

  final VoidCallback onUnlocked;

  /// 测试注入时钟。
  final DateTime Function()? now;

  final int maxAttempts;
  final Duration lockDuration;

  @override
  State<LockScreen> createState() => _LockScreenState();
}

class _LockScreenState extends State<LockScreen> {
  String _entered = '';
  String? _error;
  int _attempts = 0;
  DateTime? _lockedUntil;
  Timer? _ticker;

  DateTime get _now => widget.now?.call() ?? DateTime.now();

  bool get _locked {
    final until = _lockedUntil;
    return until != null && _now.isBefore(until);
  }

  int get _remainingSeconds {
    final until = _lockedUntil;
    if (until == null) return 0;
    final diff = until.difference(_now).inSeconds;
    return diff < 0 ? 0 : diff;
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  Future<void> _press(String key) async {
    if (_locked) return;
    if (key == '⌫') {
      if (_entered.isEmpty) return;
      setState(() {
        _entered = _entered.substring(0, _entered.length - 1);
        _error = null;
      });
      return;
    }
    if (key == '清除') {
      setState(() {
        _entered = '';
        _error = null;
      });
      return;
    }
    if (_entered.length >= widget.length) return;

    final next = '$_entered$key';
    setState(() {
      _entered = next;
      _error = null;
    });
    if (next.length == widget.length) {
      await _submit(next);
    }
  }

  Future<void> _submit(String pin) async {
    final ok = await widget.onVerify(pin);
    if (!mounted) return;
    if (ok) {
      setState(() {
        _entered = '';
        _attempts = 0;
        _error = null;
      });
      widget.onUnlocked();
      return;
    }

    final attempts = _attempts + 1;
    setState(() {
      _attempts = attempts;
      _entered = '';
      if (attempts >= widget.maxAttempts) {
        _lockedUntil = _now.add(widget.lockDuration);
        _error = '尝试次数过多，请 ${widget.lockDuration.inSeconds} 秒后再试';
      } else {
        _error = 'PIN 不正确，还可尝试 ${widget.maxAttempts - attempts} 次';
      }
    });
    if (attempts >= widget.maxAttempts) _startTicker();
  }

  void _startTicker() {
    _ticker?.cancel();
    _ticker = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      if (!_locked) {
        timer.cancel();
        setState(() {
          _lockedUntil = null;
          _attempts = 0;
          _error = null;
        });
        return;
      }
      setState(() {});
    });
  }

  @override
  Widget build(BuildContext context) {
    final palette = BeanPalette.of(context);
    final locked = _locked;

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            const Spacer(flex: 2),
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    BeanColors.gold.withValues(alpha: 0.24),
                    BeanColors.gold.withValues(alpha: 0.06),
                  ],
                ),
              ),
              child: const Icon(Icons.spa_rounded, size: 30, color: BeanColors.gold),
            ),
            const SizedBox(height: 18),
            const Text(
              '输入 PIN 解锁',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 22),
            _Dots(filled: _entered.length, total: widget.length),
            const SizedBox(height: 14),
            SizedBox(
              height: 20,
              child: Text(
                locked
                    ? '请 $_remainingSeconds 秒后再试'
                    : (_error ?? ''),
                style: TextStyle(
                  fontSize: 13,
                  color: locked || _error != null
                      ? palette.alert
                      : palette.textSecondary,
                ),
              ),
            ),
            const Spacer(flex: 2),
            _Keypad(enabled: !locked, onPress: _press),
            const SizedBox(height: 18),
            Text(
              '忘记 PIN 只能重装 App（本地数据会丢失）',
              style: TextStyle(fontSize: 11, color: palette.textSecondary),
            ),
            const SizedBox(height: 10),
          ],
        ),
      ),
    );
  }
}

class _Dots extends StatelessWidget {
  const _Dots({required this.filled, required this.total});

  final int filled;
  final int total;

  @override
  Widget build(BuildContext context) {
    final palette = BeanPalette.of(context);
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        for (var i = 0; i < total; i++)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 120),
              width: 12,
              height: 12,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: i < filled ? palette.goldDeep : Colors.transparent,
                border: Border.all(
                  color: i < filled ? palette.goldDeep : palette.border,
                  width: 1.5,
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// 与记账键盘同一套视觉：白键压在砂色底座上，键高 56。
class _Keypad extends StatelessWidget {
  const _Keypad({required this.enabled, required this.onPress});

  final bool enabled;
  final ValueChanged<String> onPress;

  static const _rows = <List<String>>[
    ['1', '2', '3'],
    ['4', '5', '6'],
    ['7', '8', '9'],
    ['清除', '0', '⌫'],
  ];

  @override
  Widget build(BuildContext context) {
    final palette = BeanPalette.of(context);
    final neutral = palette.neutral;
    final keyHeight = math.min(56.0, MediaQuery.sizeOf(context).height / 12);

    return Container(
      color: neutral.sand,
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final row in _rows)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                children: [
                  for (final key in row)
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        child: Material(
                          color: enabled ? neutral.raised : neutral.disabledBg,
                          borderRadius: BorderRadius.circular(12),
                          child: InkWell(
                            borderRadius: BorderRadius.circular(12),
                            onTap: enabled ? () => onPress(key) : null,
                            child: SizedBox(
                              height: keyHeight,
                              child: Center(
                                child: Text(
                                  key,
                                  style: TextStyle(
                                    fontSize: key.length > 1 ? 15 : 22,
                                    fontWeight: FontWeight.w500,
                                    color: enabled
                                        ? palette.textSecondary
                                        : palette.textSecondary
                                            .withValues(alpha: 0.4),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
