import 'dart:async';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/update/update_controller.dart';
import '../services/update/update_models.dart';
import '../theme/tokens.dart';
import '../widgets/common.dart';
import '../widgets/release_notes_view.dart';

/// 更新详情页：说明、下载进度、安装入口与失败恢复。
class UpdatePage extends StatefulWidget {
  const UpdatePage({
    super.key,
    required this.controller,
    this.autoStart = true,
  });

  final UpdateController controller;
  final bool autoStart;

  @override
  State<UpdatePage> createState() => _UpdatePageState();
}

class _UpdatePageState extends State<UpdatePage> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (widget.autoStart &&
          widget.controller.phase == UpdatePhase.available) {
        unawaited(widget.controller.download());
      }
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(widget.controller.onAppResumed());
    }
  }

  Future<void> _openReleasePage() async {
    final ok = await launchUrl(
      Uri.parse('https://github.com/mayapony/beancount/releases/latest'),
      mode: LaunchMode.externalApplication,
    );
    if (!mounted || ok) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(const SnackBar(content: Text('打不开浏览器，请手动访问 GitHub')));
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.controller,
      builder: (context, _) {
        final release = widget.controller.release;
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
            title: Text(
              release == null ? '更新' : '更新到 v${release.version}',
              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
            ),
            centerTitle: true,
          ),
          body: release == null
              ? Center(
                  child: Text(
                    '没有可更新的版本',
                    style: TextStyle(
                      fontSize: 14,
                      color: BeanPalette.of(context).textSecondary,
                    ),
                  ),
                )
              : ListView(
                  padding: const EdgeInsets.fromLTRB(
                    BeanSpace.page,
                    8,
                    BeanSpace.page,
                    40,
                  ),
                  children: [
                    _Header(release: release),
                    const SizedBox(height: BeanSpace.section),
                    const SectionTitle('更新说明'),
                    BeanCard(child: ReleaseNotesView(notes: release.notes)),
                    const SizedBox(height: BeanSpace.section),
                    _StatusCard(
                      controller: widget.controller,
                      onOpenReleasePage: _openReleasePage,
                    ),
                  ],
                ),
        );
      },
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.release});

  final UpdateRelease release;

  @override
  Widget build(BuildContext context) {
    final palette = BeanPalette.of(context);
    return Row(
      children: [
        Container(
          width: 52,
          height: 52,
          decoration: BoxDecoration(
            color: BeanColors.gold.withValues(alpha: 0.16),
            borderRadius: BorderRadius.circular(14),
          ),
          child: const Icon(
            Icons.system_update_rounded,
            size: 28,
            color: BeanColors.goldDeep,
          ),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '金豆 v${release.version}',
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.3,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                '${release.sizeLabel} · 来自 GitHub Releases',
                style: TextStyle(fontSize: 13, color: palette.textSecondary),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _StatusCard extends StatelessWidget {
  const _StatusCard({
    required this.controller,
    required this.onOpenReleasePage,
  });

  final UpdateController controller;
  final Future<void> Function() onOpenReleasePage;

  @override
  Widget build(BuildContext context) {
    final palette = BeanPalette.of(context);
    final phase = controller.phase;

    Widget content;
    switch (phase) {
      case UpdatePhase.idle:
      case UpdatePhase.checking:
        content = const Row(
          children: [
            SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            SizedBox(width: 12),
            Text('检查更新中…', style: TextStyle(fontSize: 14)),
          ],
        );
      case UpdatePhase.available:
        content = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('准备好后开始下载', style: TextStyle(fontSize: 14)),
            const SizedBox(height: 12),
            FilledButton(
              key: const ValueKey('update-download'),
              onPressed: controller.download,
              child: const Text('下载'),
            ),
          ],
        );
      case UpdatePhase.downloading:
        final total = controller.totalBytes;
        final received = controller.receivedBytes ?? 0;
        content = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(3),
              child: LinearProgressIndicator(
                key: const ValueKey('update-progress'),
                value: controller.progress,
                minHeight: 6,
                backgroundColor: palette.neutral.track,
                valueColor: const AlwaysStoppedAnimation<Color>(
                  BeanColors.goldDeep,
                ),
              ),
            ),
            const SizedBox(height: 10),
            Text(
              total == null
                  ? '已下载 ${formatBytes(received)}'
                  : '${formatBytes(received)} / ${formatBytes(total)}',
              style: TextStyle(fontSize: 13, color: palette.textSecondary),
            ),
            const SizedBox(height: 4),
            TextButton(
              key: const ValueKey('update-cancel'),
              onPressed: controller.cancelDownload,
              style: TextButton.styleFrom(padding: EdgeInsets.zero),
              child: const Text('取消下载'),
            ),
          ],
        );
      case UpdatePhase.ready:
        content = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.check_circle_rounded,
                    size: 20, color: BeanColors.beanGreen),
                const SizedBox(width: 8),
                const Text('下载完成，可以安装', style: TextStyle(fontSize: 14)),
              ],
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                key: const ValueKey('update-install'),
                onPressed: controller.install,
                child: const Text('安装'),
              ),
            ),
          ],
        );
      case UpdatePhase.requestingPermission:
        content = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(
                  Icons.app_settings_alt_rounded,
                  size: 20,
                  color: BeanColors.goldDeep,
                ),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text(
                    '请允许金豆安装未知应用',
                    style: TextStyle(fontSize: 14),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              '已打开系统设置。授权后返回金豆会自动继续安装；如果设置页没有弹出，点下面的按钮。',
              style: TextStyle(
                fontSize: 13,
                height: 1.45,
                color: palette.textSecondary,
              ),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              children: [
                FilledButton(
                  key: const ValueKey('update-permission-open'),
                  onPressed: controller.openInstallSettings,
                  child: const Text('打开设置'),
                ),
                TextButton(
                  key: const ValueKey('update-permission-continue'),
                  onPressed: controller.install,
                  child: const Text('已授权，继续'),
                ),
              ],
            ),
          ],
        );
      case UpdatePhase.installing:
        content = Row(
          children: [
            const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                '正在打开系统安装器…如果没反应，请回到桌面查看系统提示',
                style: TextStyle(fontSize: 14, color: palette.textSecondary),
              ),
            ),
          ],
        );
      case UpdatePhase.failed:
        content = _failureContent(context);
      case UpdatePhase.upToDate:
        content = const Row(
          children: [
            Icon(Icons.check_circle_rounded,
                size: 20, color: BeanColors.beanGreen),
            SizedBox(width: 8),
            Text('已是最新版本', style: TextStyle(fontSize: 14)),
          ],
        );
    }

    return BeanCard(child: content);
  }

  Widget _failureContent(BuildContext context) {
    final failure = controller.failure;
    final kind = failure?.kind;
    final isPermission = kind == UpdateFailureKind.permission;
    final isInstallBlocked = kind == UpdateFailureKind.signature ||
        kind == UpdateFailureKind.downgrade ||
        kind == UpdateFailureKind.versionName ||
        kind == UpdateFailureKind.parse ||
        kind == UpdateFailureKind.noInstaller;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.error_outline_rounded,
                size: 20, color: BeanColors.alertRed),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                failure?.message ?? '更新失败，请重试',
                style: const TextStyle(fontSize: 14, height: 1.45),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        if (isPermission)
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              FilledButton(
                key: const ValueKey('update-permission'),
                onPressed: controller.openInstallSettings,
                child: const Text('去设置'),
              ),
              TextButton(
                key: const ValueKey('update-permission-retry'),
                onPressed: controller.install,
                child: const Text('已授权，重试'),
              ),
            ],
          )
        else if (isInstallBlocked)
          Wrap(
            spacing: 8,
            children: [
              TextButton(
                key: const ValueKey('update-release-page'),
                onPressed: onOpenReleasePage,
                child: const Text('打开 Release 页'),
              ),
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('返回'),
              ),
            ],
          )
        else
          FilledButton(
            key: const ValueKey('update-retry'),
            onPressed: controller.downloadPath == null
                ? controller.download
                : controller.install,
            child: const Text('重试'),
          ),
      ],
    );
  }
}
