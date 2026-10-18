/// 「测试识别」用的合成小票（340×220 PNG，3 KB）。
///
/// 内容是固定的 ASCII 小票：
///
/// ```
/// TEST RECEIPT
/// DEMO MARKET
/// TOTAL 12.34
/// 2026-10-18 12:34:56
/// ```
///
/// 金额必须是 [kProbeAmountCents]（12.34 元 = 1234 分）。用内置图片而不是运行时
/// 画一张，是为了不依赖系统字体，也能在任何测试环境里跑。
library;

import 'dart:convert';
import 'dart:typed_data';

/// 合成小票的金额（分）：模型读出这个数才算「识别正常」。
const int kProbeAmountCents = 1234;

/// 合成小票的像素尺寸。
const int kProbeImageWidth = 340;
const int kProbeImageHeight = 220;

const String _probePngBase64 =
    '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'
    'AElFTkSuQmCC';

/// 解码出 PNG 字节（每次调用都重新解码，调用频率极低）。
Uint8List probeReceiptImage() => base64Decode(_probePngBase64);
