import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../services/export/export_service.dart';
import '../theme/tokens.dart';
import '../widgets/common.dart';

/// 把导出产物交给系统保存对话框（SAF / 另存为）。
///
/// 返回保存位置的人类可读描述；返回 null 表示用户取消。
typedef ExportSaver = Future<String?> Function(ExportFile file);

/// 默认实现：`FilePicker.saveFile` 是 Android 11+ 唯一能被用户看到的写文件路径。
Future<String?> saveWithFilePicker(ExportFile file) async {
  final extension = file.fileName.split('.').last;
  final path = await FilePicker.platform.saveFile(
    dialogTitle: '保存到',
    fileName: file.fileName,
    bytes: file.bytes,
    type: FileType.custom,
    allowedExtensions: [extension],
  );
  if (path == null) return null;
  // Android 的 SAF 只回一个 uri 描述，桌面回真实路径
  return path;
}

/// 导出页：设置 →「导出」。
class ExportPage extends StatefulWidget {
  const ExportPage({
    super.key,
    required this.service,
    this.save,
  });

  final ExportService service;

  /// 测试注入用；为空时走系统保存对话框。
  final ExportSaver? save;

  @override
  State<ExportPage> createState() => _ExportPageState();
}

enum _Phase { idle, building, done, failed }

class _ExportPageState extends State<ExportPage> {
  _Phase _phase = _Phase.idle;
  ExportSummary? _summary;
  ExportFile? _last;
  String? _location;
  String? _error;
  String? _busyLabel;

  @override
  void initState() {
    super.initState();
    _loadSummary();
  }

  Future<void> _loadSummary() async {
    try {
      final summary = await widget.service.summary();
      if (!mounted) return;
      setState(() => _summary = summary);
    } catch (_) {
      // 规模只是提示，读不到不阻塞导出
    }
  }

  Future<void> _export({required bool backup}) async {
    if (_phase == _Phase.building) return;
    setState(() {
      _phase = _Phase.building;
      _busyLabel = backup ? '正在打包账本与图片…' : '正在生成 CSV…';
      _error = null;
      _last = null;
      _location = null;
    });

    try {
      final file = backup
          ? await widget.service.buildBackup()
          : await widget.service.buildCsv();
      final save = widget.save ?? saveWithFilePicker;
      final location = await save(file);
      if (!mounted) return;

      if (location == null) {
        // 用户取消：不报成功，也不留任何痕迹
        setState(() {
          _phase = _Phase.idle;
          _busyLabel = null;
        });
        return;
      }

      setState(() {
        _phase = _Phase.done;
        _last = file;
        _location = location;
        _busyLabel = null;
        _summary = ExportSummary(
          entryCount: file.entryCount,
          imageCount: file.imageCount,
        );
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _phase = _Phase.failed;
        _error = '$error';
        _busyLabel = null;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = BeanPalette.of(context);
    final busy = _phase == _Phase.building;
    final summary = _summary;

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        leading: IconButton(
          tooltip: '返回',
          icon: const Icon(Icons.chevron_left_rounded, size: 28),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: const Text(
          '导出',
          style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
        ),
        centerTitle: true,
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(
          BeanSpace.page,
          8,
          BeanSpace.page,
          40,
        ),
        children: [
          Text(
            summary == null
                ? '读取账本规模…'
                : '${summary.entryCount} 笔账 · ${summary.imageCount} 张图',
            style: TextStyle(fontSize: 13, color: palette.textSecondary),
          ),
          const SizedBox(height: BeanSpace.section),
          BeanCard(
            padding: EdgeInsets.zero,
            child: Column(
              children: [
                _ExportTile(
                  title: '导出 CSV',
                  subtitle: '只有账目，不含图片；可以再导入回来',
                  icon: Icons.table_view_rounded,
                  enabled: !busy,
                  onTap: () => _export(backup: false),
                ),
                Divider(
                  height: BeanSpace.hairline,
                  thickness: BeanSpace.hairline,
                  indent: 62,
                  color: palette.border,
                ),
                _ExportTile(
                  title: '完整备份 zip',
                  subtitle: '含全部票据图片，可换设备还原',
                  icon: Icons.inventory_2_rounded,
                  enabled: !busy,
                  onTap: () => _export(backup: true),
                ),
              ],
            ),
          ),
          if (busy) ...[
            const SizedBox(height: BeanSpace.section),
            Row(
              children: [
                const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                const SizedBox(width: 10),
                Text(
                  _busyLabel ?? '正在导出…',
                  style: TextStyle(fontSize: 13, color: palette.textSecondary),
                ),
              ],
            ),
          ],
          if (_phase == _Phase.done && _last != null) ...[
            const SizedBox(height: BeanSpace.section),
            BeanCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        Icons.check_circle_rounded,
                        size: 18,
                        color: palette.income,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          '已导出 ${_last!.fileName}',
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '${_last!.readableSize} · ${_directoryOf(_location)}',
                    style: TextStyle(
                      fontSize: 12,
                      color: palette.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
          ],
          if (_phase == _Phase.failed) ...[
            const SizedBox(height: BeanSpace.section),
            BeanCard(
              child: Row(
                children: [
                  Icon(
                    Icons.error_outline_rounded,
                    size: 18,
                    color: palette.alert,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '导出失败：$_error',
                      style: TextStyle(fontSize: 13, color: palette.alert),
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: BeanSpace.section),
          Text(
            '导出的 CSV 与备份包都使用 BeeCount 兼容格式：既能再导入金豆，也能交给 BeeCount。',
            style: TextStyle(fontSize: 12, color: palette.textSecondary),
          ),
        ],
      ),
    );
  }
}

/// 成功卡片里的位置：只留目录，文件名已经在上面的标题里了。
String _directoryOf(String? location) {
  if (location == null || location.isEmpty) return '';
  final at = location.lastIndexOf(RegExp(r'[/\\]'));
  if (at <= 0) return location;
  return '${location.substring(0, at)}/';
}

class _ExportTile extends StatelessWidget {  const _ExportTile({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.enabled,
    required this.onTap,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = BeanPalette.of(context);
    return InkWell(
      onTap: enabled ? onTap : null,
      child: Opacity(
        opacity: enabled ? 1 : 0.45,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: palette.neutral.sand,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, size: 18, color: palette.textSecondary),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: TextStyle(
                        fontSize: 12,
                        color: palette.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.chevron_right_rounded,
                size: 20,
                color: palette.textSecondary,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
