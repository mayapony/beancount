library;

/// 捕获渠道。
enum CaptureSource { accessibility, notification, screenshot }

/// 捕获方向。
enum CaptureDirection { expense, income, refund }

/// 合并窗口：同包同金额、时间差不超过 120 秒的候选视为同一笔。
const captureMergeWindow = Duration(seconds: 120);

/// 一笔自动捕获候选：无障碍 / 通知 / 截图三条来源之一产出，等去重后入账。
class CaptureCandidate {
  const CaptureCandidate({
    required this.source,
    required this.direction,
    this.packageName,
    this.amountCents,
    this.note,
    this.happenedAt,
    this.rawText,
    this.surfaceFingerprint,
  });

  /// 捕获渠道（无障碍 / 通知 / 截图）。
  final CaptureSource source;

  /// 收支方向（付款 / 收款 / 退款）。
  final CaptureDirection direction;

  /// 来源应用包名（如 `com.tencent.mm`）；截图路径可能为空。
  final String? packageName;

  /// 金额（分）；尚未解析出时为 null。
  final int? amountCents;

  /// 商家 / 备注线索，落库时写入交易备注。
  final String? note;

  /// 发生时间；缺省由入账时补当前时间。
  final DateTime? happenedAt;

  /// 原始文本（通知全文或控件树拼接文本）；不落库，仅用于规则学习。
  final String? rawText;

  /// 页面结构指纹（无障碍抓屏时）；通知 / 截图路径为空。
  final String? surfaceFingerprint;

  bool get hasAmount => amountCents != null && amountCents! > 0;

  /// 合并键：同一来源应用 + 同一金额，视为同一笔的候选。
  ///
  /// 时间维度由 [captureMergeWindow] 另行判断，不进键——避免把 120 秒窗口
  /// 切成硬桶导致「相邻两笔相差 2 秒却落在两个桶」漏合并。
  String? get mergeKey {
    final amount = amountCents;
    if (amount == null || amount <= 0) return null;
    return '${packageName ?? ''}|$amount';
  }
}
