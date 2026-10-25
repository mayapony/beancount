library;

import 'dart:async';

import 'package:flutter/foundation.dart' show debugPrint;

import '../../data/db/app_database.dart';
import '../../data/repositories/app_state_repository.dart';
import 'candidate_merge.dart';
import 'capture_candidate.dart';
import 'capture_entry_saver.dart';
import 'capture_rule.dart';
import 'capture_rule_executor.dart';
import 'capture_settings.dart';
import 'capture_tree.dart';

/// 入账完成后的通知出口：由运行它的引擎实现（headless 侧走 MethodChannel 到原生）。
abstract class CaptureNotifier {
  Future<void> notifyEntry({required int amountCents, required String note});
}

/// 后台捕获引擎的运行时管线。
///
/// 事件 → 规则匹配（仅 grey / active，pending 不自动入账）→ 套用执行器 →
/// 产出候选 → 短窗口去重合并 → `EntryWriter` 入账 + 通知。
///
/// 未命中时什么都不写：原生侧环形缓冲已留着树快照，截图兜底（8.x）会把它当
/// 留证取走生成规则。同一笔支付的通知与页面几乎同时到达，短缓冲把它们合到一次
/// flush 里，再由 [mergeCandidates] 按「包名 + 金额 + 时间窗」去重。
class CaptureRuntime {
  CaptureRuntime({
    required this.db,
    required this.notifier,
    this.flushDelay = const Duration(seconds: 3),
    DateTime Function()? clock,
    void Function(String)? log,
  })  : _clock = clock ?? DateTime.now,
        _log = log;

  final AppDatabase db;
  final CaptureNotifier notifier;

  /// 一次 flush 的合并窗口：通知与无障碍几乎同时到达时，把两者收进同一批。
  final Duration flushDelay;
  final DateTime Function() _clock;
  final void Function(String)? _log;

  late final CaptureSettingsStore _settings =
      CaptureSettingsStore(AppStateRepository(db));
  late final CaptureRuleStore _rules = CaptureRuleStore(AppStateRepository(db));
  late final CaptureEntrySaver _saver = CaptureEntrySaver(db: db);

  static const _executor = CaptureRuleExecutor();

  final List<CaptureCandidate> _buffer = [];
  Timer? _flushTimer;

  /// 无障碍抓屏：白名单包的一帧控件树。
  Future<void> onTreeCaptured({
    required String packageName,
    required String dump,
  }) async {
    if (!(await _settings.load()).enabled) return;
    final tree = dumpToTree(dump);
    final fingerprint = surfaceFingerprintOf(tree);
    _log?.call('tree pkg=$packageName fp=$fingerprint nodes=${tree.totalNodeCount}');
    final rule = await _match(
      packageName: packageName,
      target: RuleTarget.accessibility,
      fingerprint: fingerprint,
    );
    if (rule == null) {
      _log?.call('tree pkg=$packageName no-rule fp=$fingerprint');
      return;
    }

    final extraction = _executor.apply(rule, tree: tree);
    if (extraction == null) {
      _log?.call('tree pkg=$packageName rule=${rule.id} no-extraction');
      return;
    }
    _log?.call('tree pkg=$packageName rule=${rule.id} amount=${extraction.amountCents}');

    _enqueue(
      CaptureCandidate(
        source: CaptureSource.accessibility,
        direction: extraction.direction,
        packageName: packageName,
        amountCents: extraction.amountCents,
        happenedAt: _clock(),
        rawText: tree.flattenedText,
        surfaceFingerprint: fingerprint,
      ),
    );
  }

  /// 通知监听：白名单包的一条支付通知文本。
  Future<void> onNotificationCaptured({
    required String packageName,
    required String text,
  }) async {
    if (!(await _settings.load()).enabled) return;
    final rule = await _match(
      packageName: packageName,
      target: RuleTarget.notification,
    );
    if (rule == null) {
      _log?.call('notif pkg=$packageName no-rule');
      return;
    }

    final extraction = _executor.apply(rule, text: text);
    if (extraction == null) {
      _log?.call('notif pkg=$packageName rule=${rule.id} no-extraction');
      return;
    }
    _log?.call('notif pkg=$packageName rule=${rule.id} amount=${extraction.amountCents}');

    _enqueue(
      CaptureCandidate(
        source: CaptureSource.notification,
        direction: extraction.direction,
        packageName: packageName,
        amountCents: extraction.amountCents,
        note: text,
        happenedAt: _clock(),
        rawText: text,
      ),
    );
  }

  /// 把缓冲里的候选合并去重后逐条入账；供测试与 flush 定时器调用。
  Future<void> flush() async {
    _flushTimer?.cancel();
    _flushTimer = null;
    if (_buffer.isEmpty) return;
    final batch = List.of(_buffer);
    _buffer.clear();
    for (final candidate in mergeCandidates(batch)) {
      await _write(candidate);
    }
  }

  void _enqueue(CaptureCandidate candidate) {
    _buffer.add(candidate);
    _flushTimer?.cancel();
    _flushTimer = Timer(flushDelay, () => unawaited(flush()));
  }

  Future<void> _write(CaptureCandidate candidate) async {
    try {
      final result = await _saver.save(candidate, now: _clock());
      await _settings.markCaptured(_clock());
      _log?.call('entry written inserted=${result.inserted} amount=${candidate.amountCents}');
      if (result.inserted) {
        await notifier.notifyEntry(
          amountCents: candidate.amountCents!,
          note: (candidate.note ?? '').trim(),
        );
      }
    } catch (error) {
      _log?.call('entry write failed: $error');
      debugPrint('capture runtime: 入账失败: $error');
    }
  }

  Future<CaptureRule?> _match({
    required String packageName,
    required RuleTarget target,
    String? fingerprint,
  }) async {
    for (final rule in await _rules.load()) {
      if (rule.packageName != packageName) continue;
      if (rule.target != target) continue;
      if (rule.tier == CaptureRuleTier.pending) continue;
      if (target == RuleTarget.accessibility) {
        if (rule.surfaceFingerprint == null ||
            rule.surfaceFingerprint != fingerprint) {
          continue;
        }
      }
      return rule;
    }
    return null;
  }

  void dispose() {
    _flushTimer?.cancel();
    _flushTimer = null;
  }
}
