import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/import/bee_count_archive.dart';
import '../services/import/bee_count_csv.dart';
import '../services/import/import_planner.dart';
import '../services/import/import_report.dart';
import '../services/import/import_service.dart';
import '../theme/tokens.dart';
import '../widgets/common.dart';

/// 从 BeeCount 导入：选文件 → 预览 → 导入 → 报告。
///
/// 预览与写入共用同一份 `ImportPlan`，所以"预览看到多少"就是"实际写多少"。
class ImportPage extends StatefulWidget {
  const ImportPage({
    super.key,
    required this.service,
    this.initialBytes,
    this.initialName,
  });

  final ImportService service;

  /// 预置文件：单测直接喂字节，省掉系统文件选择器。
  final Uint8List? initialBytes;
  final String? initialName;

  @override
  State<ImportPage> createState() => _ImportPageState();
}

enum _Stage { idle, parsing, preview, importing, done }

class _ImportPageState extends State<ImportPage> {
  _Stage _stage = _Stage.idle;
  String? _error;
  String _sourceName = '';
  ImportPlan? _plan;
  ImportReport? _report;
  Map<String, ExtractedAttachment> _attachments = const {};
  int _done = 0;
  int _total = 0;
  final List<String> _warnings = [];

  @override
  void initState() {
    super.initState();
    final bytes = widget.initialBytes;
    if (bytes != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _prepare(bytes, widget.initialName ?? '备份文件');
      });
    }
  }

  Future<void> _pick() async {
    setState(() {
      _error = null;
      _warnings.clear();
      _stage = _Stage.parsing;
    });

    try {
      final picked = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: const ['zip', 'csv'],
        withData: true,
      );
      if (picked == null || picked.files.isEmpty) {
        if (mounted) setState(() => _stage = _Stage.idle);
        return;
      }

      final file = picked.files.first;
      final bytes = file.bytes ?? Uint8List(0);
      if (bytes.isEmpty) {
        throw StateError('文件读不出来（可能是空的）');
      }

      await _prepare(bytes, file.name);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _stage = _Stage.idle;
        _error = '$error';
      });
    }
  }

  Future<void> _prepare(Uint8List bytes, String name) async {
    final export = extractBeeCountExport(bytes, name: name);
    if (!export.ok) {
      setState(() {
        _stage = _Stage.idle;
        _error = export.fatal;
      });
      return;
    }

    final parsed = parseBeeCountCsv(export.csvBytes);
    if (!parsed.ok) {
      setState(() {
        _stage = _Stage.idle;
        _error = parsed.fatal;
      });
      return;
    }

    final sizes = <String, int>{
      for (final a in export.attachments) a.fileName: a.bytes.length,
    };

    final plan = await planImport(
      service: widget.service,
      parsed: parsed,
      attachmentSizes: sizes,
    );

    if (!mounted) return;
    setState(() {
      _sourceName = export.zipName.isEmpty ? name : export.zipName;
      _attachments = {for (final a in export.attachments) a.fileName: a};
      _plan = plan;
      _warnings
        ..clear()
        ..addAll(export.warnings)
        ..addAll(plan.attachmentWarnings.take(5));
      _stage = _Stage.preview;
    });
  }

  Future<void> _start() async {
    final plan = _plan;
    if (plan == null) return;

    setState(() {
      _stage = _Stage.importing;
      _done = 0;
      _total = plan.entries.length;
    });

    final report = await widget.service.apply(
      plan,
      attachments: _attachments,
      onProgress: (done, total) {
        if (!mounted) return;
        setState(() {
          _done = done;
          _total = total;
        });
      },
    );

    if (!mounted) return;
    setState(() {
      _report = report;
      _stage = _Stage.done;
    });
  }

  Future<void> _copyReport() async {
    final text = _report?.toText() ?? '';
    await Clipboard.setData(ClipboardData(text: text));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('报告已复制')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final palette = BeanPalette.of(context);
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: SafeArea(
        child: Column(
          children: [
            _TopBar(title: '从 BeeCount 导入'),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(
                  BeanSpace.page,
                  4,
                  BeanSpace.page,
                  32,
                ),
                children: [
                  if (_error != null) ...[
                    _ErrorCard(message: _error!),
                    const SizedBox(height: 16),
                  ],
                  ...switch (_stage) {
                    _Stage.idle => [_idle(palette)],
                    _Stage.parsing => [_busy('正在读取文件…')],
                    _Stage.preview => [_preview(palette)],
                    _Stage.importing => [_importing(palette)],
                    _Stage.done => [_doneView(palette)],
                  },
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _idle(BeanPalette palette) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        BeanCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SectionTitle('怎么拿备份'),
              Text(
                '在 BeeCount 里：设置 → 数据管理 → 导出备份，会得到一个 zip。\n'
                'zip 里包含 CSV 和附件图片；只选 CSV 也能导入，但图片不会带过来。',
                style: TextStyle(
                  fontSize: 13,
                  height: 1.5,
                  color: palette.textSecondary,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                '可以重复导入：同一笔（时间 + 金额 + 备注）只会记一次。',
                style: TextStyle(
                  fontSize: 13,
                  height: 1.5,
                  color: palette.textSecondary,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: BeanSpace.section),
        if (kIsWeb)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: _InfoCard(
              icon: Icons.desktop_windows_rounded,
              lines: [
                'Web 版只用于预览界面',
                '浏览器的沙盒里没有文件目录，图片无法落盘。请在 Android / iOS 上做真正的导入。',
              ],
            ),
          ),
        FilledButton.icon(
          onPressed: kIsWeb ? null : _pick,
          icon: const Icon(Icons.folder_open_rounded, size: 18),
          style: FilledButton.styleFrom(
            backgroundColor: BeanColors.goldDeep,
            minimumSize: const Size.fromHeight(48),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(BeanRadius.button),
            ),
          ),
          label: const Text('选择备份文件'),
        ),
      ],
    );
  }

  Widget _busy(String label) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 48),
      child: Center(
        child: Column(
          children: [
            const CircularProgressIndicator(strokeWidth: 2.5),
            const SizedBox(height: 16),
            Text(label, style: const TextStyle(fontSize: 13)),
          ],
        ),
      ),
    );
  }

  Widget _preview(BeanPalette palette) {
    final plan = _plan;
    if (plan == null) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_sourceName.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Text(
              _sourceName,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 12, color: palette.textSecondary),
            ),
          ),
        BeanCard(
          child: Row(
            children: [
              Expanded(
                child: _Stat(
                  label: '可导入',
                  value: '${plan.importable}',
                  unit: '笔',
                  color: BeanColors.goldDeep,
                ),
              ),
              Container(width: 1, height: 34, color: palette.border),
              Expanded(
                child: _Stat(
                  label: '跳过',
                  value: '${plan.skippedCount}',
                  unit: '行',
                  color: palette.textSecondary,
                ),
              ),
              Container(width: 1, height: 34, color: palette.border),
              Expanded(
                child: _Stat(
                  label: '图片',
                  value: '${plan.attachmentFiles.length}',
                  unit: '张',
                  color: palette.textSecondary,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),

        if (plan.attachmentFiles.isNotEmpty)
          _InfoCard(
            icon: Icons.image_rounded,
            lines: [
              '将导入 ${plan.attachmentFiles.length} 张图片（约 ${plan.attachmentSizeLabel}）',
            ],
          ),

        if (plan.newCategories.isNotEmpty)
          _InfoCard(
            icon: Icons.category_rounded,
            lines: [
              '新建 ${plan.newCategories.length} 个分类',
              plan.newCategories.map((c) => c.display).take(12).join('、'),
            ],
          ),

        if (plan.newAccounts.isNotEmpty)
          _InfoCard(
            icon: Icons.account_balance_wallet_rounded,
            lines: [
              '新建 ${plan.newAccounts.length} 个账户',
              plan.newAccounts.join('、'),
            ],
          ),

        if (plan.newTags.isNotEmpty)
          _InfoCard(
            icon: Icons.sell_rounded,
            lines: [
              '新建 ${plan.newTags.length} 个标签',
              plan.newTags.join('、'),
            ],
          ),

        if (plan.skipped.isNotEmpty)
          _InfoCard(
            icon: Icons.skip_next_rounded,
            lines: [
              '跳过 ${plan.skippedCount} 行',
              for (final entry in plan.skipReasons.entries)
                '· ${entry.key}：${entry.value} 行',
            ],
          ),

        if (_warnings.isNotEmpty)
          _InfoCard(
            icon: Icons.info_outline_rounded,
            lines: _warnings,
          ),

        const SizedBox(height: 16),
        FilledButton(
          onPressed: plan.isEmpty ? null : _start,
          style: FilledButton.styleFrom(
            backgroundColor: BeanColors.goldDeep,
            minimumSize: const Size.fromHeight(48),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(BeanRadius.button),
            ),
          ),
          child: Text(
            plan.isEmpty ? '没有可导入的数据' : '开始导入 ${plan.importable} 笔',
          ),
        ),
        const SizedBox(height: 8),
        TextButton(
          onPressed: _pick,
          child: const Text('重新选择文件'),
        ),
      ],
    );
  }

  Widget _importing(BeanPalette palette) {
    final progress = _total == 0 ? null : _done / _total;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 40),
      child: Column(
        children: [
          Text(
            '正在导入 $_done / $_total',
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 14),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 8,
              backgroundColor: palette.neutral.track,
              valueColor: const AlwaysStoppedAnimation<Color>(
                BeanColors.goldDeep,
              ),
            ),
          ),
          const SizedBox(height: 14),
          Text(
            '图片会逐张写入本地目录，请不要退出',
            style: TextStyle(fontSize: 12, color: palette.textSecondary),
          ),
        ],
      ),
    );
  }

  Widget _doneView(BeanPalette palette) {
    final report = _report;
    if (report == null) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        BeanCard(
          child: Row(
            children: [
              Expanded(
                child: _Stat(
                  label: '成功',
                  value: '${report.inserted}',
                  unit: '笔',
                  color: BeanColors.goldDeep,
                ),
              ),
              Container(width: 1, height: 34, color: palette.border),
              Expanded(
                child: _Stat(
                  label: '跳过',
                  value: '${report.skipped}',
                  unit: '行',
                  color: palette.textSecondary,
                ),
              ),
              Container(width: 1, height: 34, color: palette.border),
              Expanded(
                child: _Stat(
                  label: '失败',
                  value: '${report.failed}',
                  unit: '行',
                  color: report.failed == 0
                      ? palette.textSecondary
                      : BeanColors.alertRed,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        _InfoCard(
          icon: Icons.image_rounded,
          lines: [
            '附件写入 ${report.attachmentsSaved} 张，缺失 ${report.attachmentsMissing} 张',
          ],
        ),
        _InfoCard(
          icon: Icons.auto_awesome_rounded,
          lines: [
            '新建分类 ${report.newCategories} · 账户 ${report.newAccounts} · 标签 ${report.newTags}',
            '用时 ${report.elapsedLabel}',
          ],
        ),
        if (report.failures.isNotEmpty)
          _InfoCard(
            icon: Icons.error_outline_rounded,
            lines: [
              for (final item in report.failures.take(8))
                '第 ${item.lineNumber} 行：${item.reason}',
            ],
          ),
        const SizedBox(height: 16),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(),
          style: FilledButton.styleFrom(
            backgroundColor: BeanColors.goldDeep,
            minimumSize: const Size.fromHeight(48),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(BeanRadius.button),
            ),
          ),
          child: const Text('完成'),
        ),
        const SizedBox(height: 8),
        TextButton.icon(
          onPressed: _copyReport,
          icon: const Icon(Icons.copy_rounded, size: 16),
          label: const Text('复制报告'),
        ),
      ],
    );
  }
}

class _TopBar extends StatelessWidget {
  const _TopBar({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 52,
      child: Row(
        children: [
          IconButton(
            tooltip: '返回',
            onPressed: () => Navigator.of(context).pop(),
            icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 18),
          ),
          const SizedBox(width: 2),
          Text(
            title,
            style: TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w600,
              color: Theme.of(context).colorScheme.onSurface,
            ),
          ),
        ],
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({
    required this.label,
    required this.value,
    required this.unit,
    required this.color,
  });

  final String label;
  final String value;
  final String unit;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final palette = BeanPalette.of(context);
    return Column(
      children: [
        Text(
          label,
          style: TextStyle(fontSize: 11, color: palette.textSecondary),
        ),
        const SizedBox(height: 4),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Text(
              value,
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w700,
                color: color,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
            const SizedBox(width: 2),
            Text(
              unit,
              style: TextStyle(fontSize: 11, color: palette.textSecondary),
            ),
          ],
        ),
      ],
    );
  }
}

class _InfoCard extends StatelessWidget {
  const _InfoCard({required this.icon, required this.lines});

  final IconData icon;
  final List<String> lines;

  @override
  Widget build(BuildContext context) {
    final palette = BeanPalette.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: BeanCard(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 18, color: palette.neutral.iconNeutral),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (var i = 0; i < lines.length; i++)
                    Text(
                      lines[i],
                      style: TextStyle(
                        fontSize: i == 0 ? 14 : 12,
                        height: 1.5,
                        fontWeight: i == 0 ? FontWeight.w600 : FontWeight.w400,
                        color: i == 0
                            ? Theme.of(context).colorScheme.onSurface
                            : palette.textSecondary,
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ErrorCard extends StatelessWidget {
  const _ErrorCard({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return BeanCard(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(
            Icons.report_gmailerrorred_rounded,
            size: 18,
            color: BeanColors.alertRed,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(
                fontSize: 13,
                height: 1.5,
                color: BeanColors.alertRedDeep,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
