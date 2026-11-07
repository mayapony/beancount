library;

import 'capture_diagnostics.dart';
import 'capture_rule.dart';
import 'capture_settings.dart';

/// 生成一份可直接阅读的诊断报告。
///
/// 脱敏只做三件事：抹掉商户名、抹掉 6 位以上连续数字（订单号），其余原样。
/// 金额与页面指纹 MUST 保留——金额是判断「错多少」的依据，指纹是判断
/// 「规则为何不命中」的依据，抹掉导出就失去意义。
String buildCaptureDiagExport({
  required CaptureSettings settings,
  required List<CaptureRule> rules,
  required List<CaptureDiagEvent> events,
  Map<String, String> evidence = const {},
  Map<String, Object?>? serviceState,
  DateTime? now,
}) {
  final at = now ?? DateTime.now();
  final buffer = StringBuffer()
    ..writeln('金豆 · 自动记账诊断报告')
    ..writeln('生成时间: ${_stamp(at)}')
    ..writeln()
    ..writeln('[状态]')
    ..writeln('自动记账: ${settings.enabled ? '已开启' : '已关闭'}')
    ..writeln('上次捕获: ${_stampOrNever(settings.lastCaptureAt)}');
  if (serviceState != null) {
    buffer.writeln('后台服务: ${serviceState['running'] == true ? '运行中' : '未运行'}');
  }
  buffer
    ..writeln()
    ..writeln('[规则] ${rules.length} 条')
    ..writeln();
  if (rules.isEmpty) {
    buffer.writeln('（空：没有任何提取规则，自动记账不会触发）');
  } else {
    for (final rule in rules) {
      buffer.writeln(
        '- ${rule.tier.name} ${rule.packageName} ${rule.target.name} '
        'fp=${rule.surfaceFingerprint ?? '-'} '
        'strategy=${rule.amountStrategy.name} '
        'pattern=${rule.amountPattern ?? '-'} '
        'label=${rule.adjacentLabel ?? '-'} '
        'exclude=${rule.excludeKeywords.join('|')}',
      );
    }
  }
  buffer
    ..writeln()
    ..writeln('[事件] ${events.length} 条（时间正序）')
    ..writeln();
  if (events.isEmpty) buffer.writeln('（空）');
  for (final event in events) {
    buffer.writeln(_eventLine(event));
    if (event.detail.isNotEmpty) {
      for (final entry in event.detail.entries) {
        buffer.writeln('    ${entry.key}: ${_stringify(entry.value)}');
      }
    }
    final id = event.evidenceId;
    final text = id == null ? null : evidence[id];
    if (id != null) {
      buffer.writeln('    evidence: ${text ?? '（已淘汰）'}');
    }
  }
  return redactDiagText(buffer.toString(), fingerprints: _fingerprintsOf(events, rules));
}

/// 抹掉商户名与 6 位以上连续数字；[fingerprints] 里的指纹原样保留。
String redactDiagText(String text, {Set<String> fingerprints = const {}}) {
  final placeholders = <String, String>{};
  var masked = text;
  var index = 0;
  for (final fingerprint in fingerprints) {
    if (fingerprint.isEmpty) continue;
    final token = '\u0001FP${index++}\u0001';
    placeholders[token] = fingerprint;
    masked = masked.replaceAll(fingerprint, token);
  }
  masked = masked.replaceAll(RegExp(r'\d{6,}'), '######');
  masked = masked.replaceAll(RegExp('merchant[=:：]\\s*[^,\\n]+'), 'merchant: ######');
  placeholders.forEach((token, fingerprint) {
    masked = masked.replaceAll(token, fingerprint);
  });
  return masked;
}

Set<String> _fingerprintsOf(
  List<CaptureDiagEvent> events,
  List<CaptureRule> rules,
) {
  final out = <String>{
    for (final rule in rules)
      if (rule.surfaceFingerprint != null) rule.surfaceFingerprint!,
  };
  for (final event in events) {
    final value = event.detail['fingerprint']?.toString();
    if (value != null && value.isNotEmpty && value != 'null') out.add(value);
    final list = event.detail['rules'];
    if (list is List) {
      for (final item in list) {
        if (item is Map) {
          final fp = item['fingerprint']?.toString();
          if (fp != null && fp.isNotEmpty && fp != 'null') out.add(fp);
        }
      }
    }
  }
  return out;
}

String _eventLine(CaptureDiagEvent event) {
  final parts = [
    _stamp(event.at),
    event.kind.wire,
    if (event.packageName != null) event.packageName!,
    if (event.target != null) 'target=${event.target}',
    'ok=${event.ok}',
    if (event.reason != null) 'reason=${event.reason}',
    if (event.count > 1) 'count=${event.count}',
  ];
  return parts.join(' ');
}

String _stringify(Object? value) {
  if (value is Map) {
    return '{${value.entries.map((e) => '${e.key}=${_stringify(e.value)}').join(', ')}}';
  }
  if (value is List) {
    return '[${value.map(_stringify).join(', ')}]';
  }
  return value?.toString() ?? 'null';
}

String _stamp(DateTime at) {
  String two(int value) => value.toString().padLeft(2, '0');
  return '${at.year}-${two(at.month)}-${two(at.day)} '
      '${two(at.hour)}:${two(at.minute)}:${two(at.second)}';
}

String _stampOrNever(DateTime? at) => at == null ? '从未' : _stamp(at);
