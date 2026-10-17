/// 本位币（CNY）与外币之间的换算。
///
/// 全部用整数：`10000 * 7.25` 在 double 里是 `72499.999…`，乘完再 round 会在边界上抖。
library;

import 'dart:math' as math;

/// 汇率的精度：1 单位外币 = 多少本位币 × 10^6。
const int kPpmScale = 1000000;

/// 本位币金额（分）= 原币金额（分）× 汇率，四舍五入到分。
///
/// 例：10000 分（100 USD）× 7250000 ppm（7.25）→ 72500 分（725 CNY）。
int baseCentsOf({required int originalCents, required int ratePpm}) {
  if (ratePpm <= 0) {
    throw ArgumentError.value(ratePpm, 'ratePpm', '汇率必须大于 0');
  }
  final scaled = originalCents * ratePpm;
  // 加半个单位再整除 = 四舍五入（原币与汇率都非负）
  return (scaled + kPpmScale ~/ 2) ~/ kPpmScale;
}

/// 7.25 → 7250000。
int ppmOf(double rate) {
  if (rate <= 0) {
    throw ArgumentError.value(rate, 'rate', '汇率必须大于 0');
  }
  return (rate * kPpmScale).round();
}

/// 7250000 → 7.25（去掉末尾多余的 0，最多 6 位）。
String rateTextOf(int ppm) {
  var text = (ppm / kPpmScale).toStringAsFixed(6);
  while (text.contains('.') && (text.endsWith('0') || text.endsWith('.'))) {
    text = text.substring(0, text.length - 1);
  }
  return text;
}

/// 币种符号：常见的给符号，其余直接用代码。
String currencySymbolOf(String code) {
  switch (code.toUpperCase()) {
    case 'CNY':
    case 'RMB':
      return '¥';
    case 'USD':
      return r'US$';
    case 'EUR':
      return '€';
    case 'JPY':
      return 'JP¥';
    case 'HKD':
      return r'HK$';
    case 'GBP':
      return '£';
    case 'KRW':
      return '₩';
    case 'AUD':
      return r'A$';
    case 'CAD':
      return r'C$';
    case 'SGD':
      return r'S$';
    case 'THB':
      return '฿';
    default:
      return '$code ';
  }
}

/// 带符号的金额文本：`US$100.00`。
String formatForeign(int cents, String currency) {
  final value = (cents.abs() / 100).toStringAsFixed(2);
  final grouped = _groupThousands(value);
  final sign = cents < 0 ? '-' : '';
  return '$sign${currencySymbolOf(currency)}$grouped';
}

String _groupThousands(String value) {
  final parts = value.split('.');
  final digits = parts.first;
  final buffer = StringBuffer();
  for (var i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) buffer.write(',');
    buffer.write(digits[i]);
  }
  return parts.length > 1 ? '${buffer.toString()}.${parts[1]}' : buffer.toString();
}

/// 供界面判断用：这个币种要不要显示折合。
bool isBaseCurrency(String code) {
  final upper = code.toUpperCase();
  return upper == 'CNY' || upper == 'RMB';
}

/// 一个安全的默认汇率（1.0），用于新建外币账户时的初始值。
const int kUnitPpm = kPpmScale;

/// 把用户输入的汇率文本解析成 ppm；非法返回 null。
int? parseRateText(String raw) {
  final text = raw.trim().replaceAll(',', '');
  if (text.isEmpty) return null;
  final value = double.tryParse(text);
  if (value == null || value <= 0 || !value.isFinite) return null;
  // 上限 10000：防止把 100 万写成 1000000 之后金额溢出得离谱
  if (value > 10000) return null;
  return math.max(1, (value * kPpmScale).round());
}
