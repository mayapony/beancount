import 'dart:typed_data';

import 'package:image_picker/image_picker.dart';

/// 用户选中的一张图片（还在内存里，尚未落盘）。
class PickedImage {
  const PickedImage({required this.bytes, required this.fileName});

  final Uint8List bytes;
  final String fileName;

  int get size => bytes.length;
}

/// 选图来源：相册或相机。
enum ImagePickSource { gallery, camera }

/// 选图函数：返回 null 表示用户取消。
typedef ImagePickFn = Future<PickedImage?> Function(ImagePickSource source);

/// 从文件名推断扩展名；没有则回落到 jpg。
String extensionOf(String fileName) {
  final dot = fileName.lastIndexOf('.');
  if (dot < 0 || dot == fileName.length - 1) return 'jpg';
  final ext = fileName.substring(dot + 1).toLowerCase();
  if (ext.isEmpty || ext.length > 5) return 'jpg';
  return ext;
}

/// 默认实现：`image_picker` + 压缩（票据认清即可，原图几 MB 会让备份包爆炸）。
ImagePickFn systemImagePicker({ImagePicker? picker}) {
  final instance = picker ?? ImagePicker();
  var seq = 0;
  return (source) async {
    final file = await instance.pickImage(
      source: source == ImagePickSource.camera
          ? ImageSource.camera
          : ImageSource.gallery,
      maxWidth: 2560,
      imageQuality: 88,
    );
    if (file == null) return null;
    final bytes = await file.readAsBytes();
    final name = file.name.isEmpty ? 'image_$seq.jpg' : file.name;
    seq++;
    return PickedImage(
      bytes: bytes,
      fileName: '${DateTime.now().microsecondsSinceEpoch}_$seq.${
          extensionOf(name)
      }',
    );
  };
}
