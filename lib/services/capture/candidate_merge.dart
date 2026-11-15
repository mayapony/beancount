import 'capture_candidate.dart';

/// 合并同一笔支付被多条路径（通知 / 页面 / 截图）捕获产生的重复候选。
///
/// 规则按来源分：
/// - **通知**：每条推送各自成笔，不与其他通知合并——通知不会重复推送，重复推送
///   就是真的两笔；把它并掉会**丢账**，而重复的账用户删得掉，丢的账看不见。
/// - **无障碍 / 截图**：只与「本批已保留的候选」或「窗口内已入账的记忆」合并。
///   这正是「停在支付结果页反复抓帧」被压成一笔的地方；合并方向是后来的并进
///   先前的，所以也不会连锁吞掉第二条通知。
/// - 无金额或无时间信息的候选无法判定是否同一笔，原样保留，交给写库时的去重键兜底。
List<CaptureCandidate> mergeCandidates(
  List<CaptureCandidate> candidates, {
  List<CaptureCandidate> recent = const <CaptureCandidate>[],
}) {
  final ordered = [...candidates]..sort((a, b) {
      final ta = a.happenedAt;
      final tb = b.happenedAt;
      if (ta == null || tb == null) return 0;
      return ta.compareTo(tb);
    });

  final kept = <CaptureCandidate>[];
  final keptNotifications = <CaptureCandidate>[];
  final keptOthers = <CaptureCandidate>[];

  for (final candidate in ordered) {
    if (candidate.mergeKey == null || candidate.happenedAt == null) {
      kept.add(candidate);
      continue;
    }

    if (candidate.source == CaptureSource.notification) {
      keptNotifications.add(candidate);
      kept.add(candidate);
      continue;
    }

    final merged = keptNotifications.any((other) => _samePayment(other, candidate)) ||
        keptOthers.any((other) => _samePayment(other, candidate)) ||
        recent.any((other) => _samePayment(other, candidate));
    if (merged) continue;

    keptOthers.add(candidate);
    kept.add(candidate);
  }

  return kept;
}

/// 同一笔支付：同 [CaptureCandidate.mergeKey] 且时间差不超过
/// [captureMergeWindow]。
bool _samePayment(CaptureCandidate a, CaptureCandidate b) {
  final key = a.mergeKey;
  if (key == null || key != b.mergeKey) return false;
  final ta = a.happenedAt;
  final tb = b.happenedAt;
  if (ta == null || tb == null) return false;
  return ta.difference(tb).abs() <= captureMergeWindow;
}
