library;

import 'dart:async';

import 'package:flutter/foundation.dart' show debugPrint;

import '../../data/db/app_database.dart';
import '../../data/repositories/app_state_repository.dart';
import 'candidate_merge.dart';
import 'capture_candidate.dart';
import 'capture_diagnostics.dart';
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
///
/// 每一处放弃处理的位置都会留下一条运行记录（见 [CaptureDiagnostics]），
/// 否则「为什么没记账」在真机上完全不可查。
class CaptureRuntime {
  CaptureRuntime({
    required this.db,
    required this.notifier,
    this.flushDelay = const Duration(seconds: 3),
    this.diag,
    DateTime Function()? clock,
    void Function(String)? log,
  })  : _clock = clock ?? DateTime.now,
        _log = log;

  final AppDatabase db;
  final CaptureNotifier notifier;

  /// 运行记录；为 null 时只跳过记录，不影响任何判定。
  final CaptureDiagnostics? diag;

  /// 一次 flush 的合并窗口：通知与无障碍几乎同时到达时，把两者收进同一批。
  final Duration flushDelay;
  final DateTime Function() _clock;
  final void Function(String)? _log;

  late final CaptureSettingsStore _settings =
      CaptureSettingsStore(AppStateRepository(db));
  late final CaptureRuleStore _rules = CaptureRuleStore(AppStateRepository(db));
  late final CaptureEntrySaver _saver = CaptureEntrySaver(db: db);

  static const _executor = CaptureRuleExecutor();

  /// 诊断记录里页面文本 / 通知文本的截断长度：够判断，又不至于把环形撑大。
  static const _snippetLength = 200;

  final List<CaptureCandidate> _buffer = [];
  Timer? _flushTimer;

  /// 无障碍抓屏：白名单包的一帧控件树。
  Future<void> onTreeCaptured({
    required String packageName,
    required String dump,
  }) async {
    if (!(await _settings.load()).enabled) {
      await diag?.record(
        kind: CaptureDiagKind.gateClosed,
        packageName: packageName,
        target: RuleTarget.accessibility.name,
        ok: false,
        reason: 'capture_disabled',
      );
      return;
    }
    final tree = dumpToTree(dump);
    final fingerprint = surfaceFingerprintOf(tree);
    _log?.call('tree pkg=$packageName fp=$fingerprint nodes=${tree.totalNodeCount}');
    // 抓到一帧就留一条：否则「服务活着但一帧都没读到」和「根本没触发」区分不开。
    await diag?.record(
      kind: CaptureDiagKind.treeCaptured,
      packageName: packageName,
      target: RuleTarget.accessibility.name,
      detail: {
        'fingerprint': fingerprint,
        'nodes': tree.totalNodeCount,
        'text_length': tree.flattenedText.length,
      },
    );
    final match = await _match(
      packageName: packageName,
      target: RuleTarget.accessibility,
      fingerprint: fingerprint,
    );
    final rule = match.rule;
    if (rule == null) {
      _log?.call('tree pkg=$packageName no-rule fp=$fingerprint');
      await _recordNoRule(
        packageName: packageName,
        target: RuleTarget.accessibility,
        fingerprint: fingerprint,
        match: match,
        evidence: dump,
      );
      return;
    }

    final attempt = _executor.attempt(rule, tree: tree);
    final extraction = attempt.extraction;
    if (extraction == null) {
      _log?.call('tree pkg=$packageName rule=${rule.id} no-extraction');
      await _recordNoExtraction(
        packageName: packageName,
        target: RuleTarget.accessibility,
        rule: rule,
        source: tree.flattenedText,
        evidence: dump,
        fingerprint: fingerprint,
        excludedKeyword: attempt.excludedKeyword,
      );
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
    if (!(await _settings.load()).enabled) {
      await diag?.record(
        kind: CaptureDiagKind.gateClosed,
        packageName: packageName,
        target: RuleTarget.notification.name,
        ok: false,
        reason: 'capture_disabled',
      );
      return;
    }
    await diag?.record(
      kind: CaptureDiagKind.notifCaptured,
      packageName: packageName,
      target: RuleTarget.notification.name,
      detail: {'text': _snippet(text)},
    );
    final match = await _match(
      packageName: packageName,
      target: RuleTarget.notification,
      fingerprint: null,
    );
    final rule = match.rule;
    if (rule == null) {
      _log?.call('notif pkg=$packageName no-rule');
      await _recordNoRule(
        packageName: packageName,
        target: RuleTarget.notification,
        fingerprint: null,
        match: match,
        evidence: text,
      );
      return;
    }

    final attempt = _executor.attempt(rule, text: text);
    final extraction = attempt.extraction;
    if (extraction == null) {
      _log?.call('notif pkg=$packageName rule=${rule.id} no-extraction');
      await _recordNoExtraction(
        packageName: packageName,
        target: RuleTarget.notification,
        rule: rule,
        source: text,
        evidence: text,
        fingerprint: null,
        excludedKeyword: attempt.excludedKeyword,
      );
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
      await diag?.record(
        kind: CaptureDiagKind.entryWritten,
        packageName: candidate.packageName,
        target: candidate.source.name,
        ok: result.inserted,
        reason: result.inserted ? null : 'duplicate',
        detail: {
          'amount_cents': candidate.amountCents,
          'direction': candidate.direction.name,
          'account': result.accountName,
          'category': result.categoryName,
        },
      );
      if (result.inserted) {
        await notifier.notifyEntry(
          amountCents: candidate.amountCents!,
          note: (candidate.note ?? '').trim(),
        );
      }
    } catch (error) {
      _log?.call('entry write failed: $error');
      await diag?.record(
        kind: CaptureDiagKind.writeFailed,
        packageName: candidate.packageName,
        target: candidate.source.name,
        ok: false,
        reason: 'write_failed',
        detail: {
          'amount_cents': candidate.amountCents,
          'error': error.toString(),
        },
      );
      debugPrint('capture runtime: 入账失败: $error');
    }
  }

  Future<void> _recordNoRule({
    required String packageName,
    required RuleTarget target,
    required String? fingerprint,
    required _RuleMatch match,
    required String evidence,
  }) async {
    final evidenceId = await diag?.saveEvidence(evidence);
    await diag?.record(
      kind: match.pending != null
          ? CaptureDiagKind.pendingRule
          : CaptureDiagKind.noRule,
      packageName: packageName,
      target: target.name,
      ok: false,
      reason: match.pending != null ? 'rule_pending' : 'no_rule',
      evidenceId: evidenceId,
      detail: {
        'fingerprint': fingerprint,
        'rules': [
          for (final rule in match.pool)
            {
              'target': rule.target.name,
              'tier': rule.tier.name,
              'fingerprint': rule.surfaceFingerprint,
            },
        ],
      },
    );
  }

  Future<void> _recordNoExtraction({
    required String packageName,
    required RuleTarget target,
    required CaptureRule rule,
    required String source,
    required String evidence,
    required String? fingerprint,
    String? excludedKeyword,
  }) async {
    final excluded = excludedKeyword != null;
    final evidenceId = await diag?.saveEvidence(evidence);
    await diag?.record(
      kind: CaptureDiagKind.noExtraction,
      packageName: packageName,
      target: target.name,
      ok: false,
      reason: excluded ? 'excluded_keyword' : 'no_match',
      evidenceId: evidenceId,
      detail: {
        'rule': rule.id,
        if (excludedKeyword != null) 'keyword': excludedKeyword,
        'strategy': rule.amountStrategy.name,
        'pattern': rule.amountPattern,
        'label': rule.adjacentLabel,
        'fingerprint': fingerprint,
        'text': _snippet(source),
      },
    );
  }

  static String _snippet(String source) {
    final flattened = source.replaceAll(RegExp(r'\s+'), ' ').trim();
    return flattened.length <= _snippetLength
        ? flattened
        : '${flattened.substring(0, _snippetLength)}…';
  }

  Future<_RuleMatch> _match({
    required String packageName,
    required RuleTarget target,
    required String? fingerprint,
  }) async {
    final relevant = [
      for (final rule in await _rules.load())
        if (rule.packageName == packageName && rule.target == target) rule,
    ];
    CaptureRule? pending;
    for (final rule in relevant) {
      if (target == RuleTarget.accessibility) {
        if (rule.surfaceFingerprint == null ||
            rule.surfaceFingerprint != fingerprint) {
          continue;
        }
      }
      if (rule.tier == CaptureRuleTier.pending) {
        pending ??= rule;
        continue;
      }
      return _RuleMatch(rule: rule, pending: pending, pool: relevant);
    }
    return _RuleMatch(pending: pending, pool: relevant);
  }

  void dispose() {
    _flushTimer?.cancel();
    _flushTimer = null;
  }
}

/// 一次匹配的结果：命中并可用 / 同页面但待定 / 以及该包该目标下的全部规则。
class _RuleMatch {
  const _RuleMatch({this.rule, this.pending, this.pool = const []});

  final CaptureRule? rule;
  final CaptureRule? pending;
  final List<CaptureRule> pool;
}
