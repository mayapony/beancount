import 'capture_candidate.dart';

/// 合并同一笔支付被多条路径（通知 / 页面 / 截图）捕获产生的重复候选。
///
/// 规则：同 [CaptureCandidate.mergeKey]（来源包名 + 金额）且时间差不超过
/// [captureMergeWindow] 的候选视为同一笔，只保留时间最早的一条；相隔超过窗口
/// 的保留各自一条。无金额或无时间信息的候选无法判定是否同一笔，原样保留，
/// 交给写库时的去重键兜底，避免误合并丢账。
List<CaptureCandidate> mergeCandidates(List<CaptureCandidate> candidates) {
  final merged = <CaptureCandidate>[];
  final groups = <String, List<CaptureCandidate>>{};

  for (final candidate in candidates) {
    final key = candidate.mergeKey;
    final time = candidate.happenedAt;
    if (key == null || time == null) {
      merged.add(candidate);
      continue;
    }
    (groups[key] ??= <CaptureCandidate>[]).add(candidate);
  }

  for (final group in groups.values) {
    group.sort((a, b) => a.happenedAt!.compareTo(b.happenedAt!));
    DateTime? anchor;
    for (final candidate in group) {
      final time = candidate.happenedAt!;
      if (anchor == null || time.difference(anchor) > captureMergeWindow) {
        merged.add(candidate);
        anchor = time;
      }
      // 落在 anchor 窗口内的视为同一笔，丢弃。
    }
  }

  return merged;
}
