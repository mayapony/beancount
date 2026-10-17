import 'dart:async';

import 'package:flutter/material.dart';

import '../data/repositories/lock_repository.dart';
import '../pages/lock_screen.dart';

/// 应用锁的闸门：读锁状态，决定先显示锁屏还是直接进 App。
///
/// 包住整棵树而不是走路由：路由能被返回键绕回，整树替换不会。
class LockGate extends StatefulWidget {
  const LockGate({
    super.key,
    required this.child,
    required this.repository,
    this.gracePeriod = const Duration(minutes: 1),
    this.now,
  });

  final Widget child;
  final LockRepository repository;

  /// 退到后台超过这个时长，回来要重新解锁。
  final Duration gracePeriod;

  /// 测试注入时钟。
  final DateTime Function()? now;

  @override
  State<LockGate> createState() => _LockGateState();
}

class _LockGateState extends State<LockGate> with WidgetsBindingObserver {
  bool _loaded = false;
  bool _enabled = false;
  bool _unlocked = false;
  int _pinLength = 6;
  DateTime? _pausedAt;

  DateTime get _now => widget.now?.call() ?? DateTime.now();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _load();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  Future<void> _load() async {
    var enabled = false;
    var length = 6;
    try {
      enabled = await widget.repository.isEnabled();
      length = await widget.repository.pinLength();
    } catch (_) {
      // 读不到就当没开：不能因为存储异常把用户锁在门外
      enabled = false;
    }
    if (!mounted) return;
    setState(() {
      _enabled = enabled;
      _pinLength = length;
      _unlocked = !enabled;
      _loaded = true;
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden) {
      _pausedAt = _now;
      return;
    }
    if (state != AppLifecycleState.resumed) return;
    final pausedAt = _pausedAt;
    _pausedAt = null;
    if (!_enabled || pausedAt == null) return;
    if (_now.difference(pausedAt) >= widget.gracePeriod) {
      setState(() => _unlocked = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_loaded) return const SizedBox.shrink();
    if (!_enabled || _unlocked) return widget.child;

    return LockScreen(
      length: _pinLength,
      now: widget.now,
      onVerify: widget.repository.verify,
      onUnlocked: () => setState(() => _unlocked = true),
    );
  }
}
