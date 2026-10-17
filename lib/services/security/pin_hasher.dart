import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

/// PIN 摘要：随机盐 + SHA-256 迭代，不保存明文。
///
/// 威胁模型要说清楚：4 位 PIN 只有 1 万种可能，散列强度不是防线，
/// **迭代成本 + 错误限速** 才是。这里的目标是"拿到数据库副本也无法一眼读出 PIN"。
class PinDigest {
  const PinDigest({required this.salt, required this.digest, required this.length});

  /// base64 编码的随机盐。
  final String salt;

  /// base64 编码的摘要。
  final String digest;

  /// PIN 长度（用于界面画几个圆点）。
  final int length;
}

/// 散列参数：迭代次数固定，未来提高时旧记录仍可校验（参数随摘要一起存）。
const int kPinIterations = 10000;

/// PIN 允许的长度。
const int kPinMinLength = 4;
const int kPinMaxLength = 6;

bool isValidPin(String pin) {
  if (pin.length < kPinMinLength || pin.length > kPinMaxLength) return false;
  return RegExp(r'^\d+$').hasMatch(pin);
}

/// 生成随机盐（16 字节）。
String generateSalt([Random? random]) {
  final rng = random ?? Random.secure();
  final bytes = Uint8List(16);
  for (var i = 0; i < bytes.length; i++) {
    bytes[i] = rng.nextInt(256);
  }
  return base64Encode(bytes);
}

/// 计算 (salt, pin) 的迭代摘要。
String hashPin({
  required String pin,
  required String salt,
  int iterations = kPinIterations,
}) {
  final saltBytes = utf8.encode(salt);
  var block = Uint8List.fromList(<int>[...saltBytes, ...utf8.encode(pin)]);
  for (var i = 0; i < iterations; i++) {
    block = Uint8List.fromList(sha256.convert(block).bytes + saltBytes);
  }
  return base64Encode(block.sublist(0, 32));
}

/// 用新盐生成一份摘要。
PinDigest digestPin(String pin, {Random? random, int iterations = kPinIterations}) {
  if (!isValidPin(pin)) {
    throw ArgumentError.value(pin, 'pin', 'PIN 必须是 $kPinMinLength–$kPinMaxLength 位数字');
  }
  final salt = generateSalt(random);
  return PinDigest(
    salt: salt,
    digest: hashPin(pin: pin, salt: salt, iterations: iterations),
    length: pin.length,
  );
}

/// 常量时间比较，避免计时侧信道。
bool verifyPin({
  required String pin,
  required String salt,
  required String digest,
  int iterations = kPinIterations,
}) {
  if (pin.isEmpty) return false;
  final candidate = hashPin(pin: pin, salt: salt, iterations: iterations);
  if (candidate.length != digest.length) return false;
  var diff = 0;
  for (var i = 0; i < candidate.length; i++) {
    diff |= candidate.codeUnitAt(i) ^ digest.codeUnitAt(i);
  }
  return diff == 0;
}
