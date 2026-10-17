import 'package:flutter/painting.dart' show Color;

/// `Color` → ARGB32 整数（数据库里存的就是它）。
///
/// 不用 `Color.value`（已废弃），也不用 `toARGB32()`（本 Flutter 版本尚未提供）。
int argbOf(Color c) => ((c.a * 255).round() << 24) |
    ((c.r * 255).round() << 16) |
    ((c.g * 255).round() << 8) |
    (c.b * 255).round();
