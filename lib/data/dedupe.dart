/// 交易去重键：`(发生时间到秒, 金额分, 规范化备注)` 的稳定散列。
///
/// 转账额外把**转入账户**纳入：同一时刻、同金额、同备注的两笔转账去向不同，
/// 不该被当成重复。非转账不传该参数，拼出的字节与旧版完全一致——历史键无需重算。
///
/// 为什么不用 `hashCode`：Dart 的 `String.hashCode` 不保证跨进程/跨版本稳定，
/// 而导入幂等要求"同一份文件在任何一次运行里都算出同一个键"。
///
/// 为什么不用标准的 FNV-1a 64 位：Web 上 Dart 的 int 是 double，`& 0xFFFF...`
/// 与大于 2^53 的乘法都会丢位，同一份文件在 Web 与移动端会算出不同的键。
/// 这里改用两个「小乘数 + 2^31-1 取模」的多项式散列并行，所有中间值都 < 2^53，
/// 各平台结果一致。
String dedupeKeyFor({
  required DateTime happenedAt,
  required int amountCents,
  required String note,
  String? toAccountId,
  String? salt,
}) {
  final seconds = DateTime(
    happenedAt.year,
    happenedAt.month,
    happenedAt.day,
    happenedAt.hour,
    happenedAt.minute,
    happenedAt.second,
  ).millisecondsSinceEpoch ~/ 1000;

  final base = toAccountId == null
      ? '$seconds|$amountCents|${note.trim()}'
      : '$seconds|$amountCents|${note.trim()}|to:$toAccountId';
  // salt 只用于「循环补记」这类需要按规则+期数区分的场景；为空时字节与旧版一致
  final source = (salt == null || salt.isEmpty) ? base : '$base|$salt';

  final a = _polyHash(source, 131);
  final b = _polyHash(source, 1000003);
  return a.toRadixString(16).padLeft(8, '0') +
      b.toRadixString(16).padLeft(8, '0');
}

const _mod = 0x7FFFFFFF; // 2^31 - 1，Mersenne 素数

int _polyHash(String source, int multiplier) {
  var hash = 0x2F1E;
  for (final unit in source.codeUnits) {
    hash = (hash * multiplier + unit) % _mod;
  }
  return hash;
}
