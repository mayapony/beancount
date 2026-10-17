import 'dart:io';
import 'dart:typed_data';

import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'receipt_recognizer.dart';

/// Android/iOS 上的本地识别：ML Kit 中文模型，完全离线。
class MlKitReceiptRecognizer implements ReceiptRecognizer {
  TextRecognizer? _recognizer;
  int _seq = 0;

  TextRecognizer get _engine {
    // 中文脚本要显式指定；默认是拉丁脚本，认不出汉字。
    return _recognizer ??=
        TextRecognizer(script: TextRecognitionScript.chinese);
  }

  @override
  Future<String?> recognizeText(Uint8List bytes) async {
    final dir = await getTemporaryDirectory();
    final file = File(p.join(dir.path, 'receipt_${_seq++}.png'));
    await file.writeAsBytes(bytes, flush: true);
    try {
      final result = await _engine.processImage(
        InputImage.fromFilePath(file.path),
      );
      final text = result.text.trim();
      return text.isEmpty ? null : text;
    } finally {
      // 临时文件用完就删：识别链路不该在磁盘上留痕
      if (await file.exists()) {
        await file.delete();
      }
    }
  }

  @override
  Future<void> close() async {
    await _recognizer?.close();
    _recognizer = null;
  }
}
