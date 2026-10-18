import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/update/app_version.dart';
import '../services/update/update_controller.dart';
import '../theme/tokens.dart';
import '../widgets/common.dart';
import '../widgets/update_prompt_sheet.dart';
import 'update_page.dart';

/// 设置 →「关于金豆」：真实版本、仓库链接与更新隐私说明。
///
/// 版本只从平台包信息读取；读不到时显示「版本未知」，不写死任何数字。
class AboutPage extends StatefulWidget {
  const AboutPage({super.key, this.versionLoader, this.controller});

  /// 测试注入；为空时走 [loadAppVersion]。
  final Future<AppVersion> Function()? versionLoader;

  /// 为空时（Web/iOS/测试）不显示更新入口。
  final UpdateController? controller;

  static final Uri repositoryUrl =
      Uri.parse('https://github.com/mayapony/beancount');

  @override
  State<AboutPage> createState() => _AboutPageState();
}

class _AboutPageState extends State<AboutPage> {
  AppVersion? _version;

  @override
  void initState() {
    super.initState();
    _loadVersion();
  }

  Future<void> _loadVersion() async {
    final loader = widget.versionLoader ?? loadAppVersion;
    AppVersion version;
    try {
      version = await loader();
    } catch (_) {
      version = AppVersion.unknown;
    }
    if (!mounted) return;
    setState(() => _version = version);
  }

  Future<void> _openRepository() async {
    final ok = await launchUrl(
      AboutPage.repositoryUrl,
      mode: LaunchMode.externalApplication,
    );
    if (!mounted || ok) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(const SnackBar(content: Text('打不开浏览器，请手动访问 GitHub')));
  }

  void _notify(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _checkUpdates() async {
    final controller = widget.controller;
    if (controller == null) return;
    final release = await controller.checkManually();
    if (!mounted) return;
    if (release != null) {
      await showUpdatePrompt(context, controller);
      return;
    }
    switch (controller.phase) {
      case UpdatePhase.upToDate:
        _notify('已是最新版本');
      case UpdatePhase.failed:
        _notify(controller.failure?.message ?? '检查更新失败');
      default:
        break;
    }
  }

  Future<void> _openUpdatePage() async {
    final controller = widget.controller;
    if (controller == null) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => UpdatePage(controller: controller),
      ),
    );
  }

  bool _canCheck(UpdateController controller) =>
      controller.phase != UpdatePhase.checking &&
      controller.phase != UpdatePhase.downloading &&
      controller.phase != UpdatePhase.installing;

  String _statusText(UpdateController controller) {
    final release = controller.release;
    return switch (controller.phase) {
      UpdatePhase.checking => '正在检查…',
      UpdatePhase.upToDate => '已是最新版本',
      UpdatePhase.available =>
        release == null ? '发现新版本' : '发现 v${release.version}',
      UpdatePhase.downloading => '正在下载…',
      UpdatePhase.ready => '下载完成，等待安装',
      UpdatePhase.installing => '等待系统安装器',
      UpdatePhase.failed => controller.failure?.message ?? '检查失败',
      UpdatePhase.idle =>
        controller.lastCheckedAt == null ? '还没检查过' : '点击检查',
    };
  }

  String _lastCheckLabel(UpdateController controller) {
    final at = controller.lastCheckedAt;
    if (at == null) return '还没检查过更新';
    final local = at.toLocal();
    return '上次检查：${local.year}-${_two(local.month)}-${_two(local.day)} '
        '${_two(local.hour)}:${_two(local.minute)}';
  }

  static String _two(int value) => value.toString().padLeft(2, '0');

  Widget _updateSection(BuildContext context) {
    final controller = widget.controller!;
    final palette = BeanPalette.of(context);
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final release = controller.release;
        final showOpen = release != null &&
            (controller.phase == UpdatePhase.available ||
                controller.phase == UpdatePhase.downloading ||
                controller.phase == UpdatePhase.ready ||
                controller.phase == UpdatePhase.installing);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SectionTitle('更新'),
            BeanCard(
              padding: EdgeInsets.zero,
              child: Column(
                children: [
                  SwitchListTile.adaptive(
                    key: const ValueKey('about-auto-check'),
                    value: controller.autoCheckEnabled,
                    onChanged: controller.setAutoCheck,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 2,
                    ),
                    secondary: Container(
                      width: 29,
                      height: 29,
                      decoration: BoxDecoration(
                        color: BeanColors.goldDeep,
                        borderRadius: BorderRadius.circular(7),
                      ),
                      child: const Icon(
                        Icons.system_update_rounded,
                        size: 18,
                        color: Colors.white,
                      ),
                    ),
                    title: const Text(
                      '自动检查更新',
                      style: TextStyle(fontSize: 16, height: 1.25),
                    ),
                    subtitle: Text(
                      '每 24 小时最多一次；关闭后不自动联网',
                      style: TextStyle(
                        fontSize: 13,
                        color: palette.textSecondary,
                      ),
                    ),
                  ),
                  Divider(
                    height: BeanSpace.hairline,
                    thickness: BeanSpace.hairline,
                    indent: 60,
                    color: palette.border,
                  ),
                  ListTile(
                    key: const ValueKey('about-check-update'),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 2,
                    ),
                    title: const Text(
                      '检查更新',
                      style: TextStyle(fontSize: 16, height: 1.25),
                    ),
                    subtitle: Text(
                      _statusText(controller),
                      style: TextStyle(
                        fontSize: 13,
                        color: palette.textSecondary,
                      ),
                    ),
                    trailing: controller.phase == UpdatePhase.checking
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Icon(
                            Icons.chevron_right_rounded,
                            size: 20,
                            color: palette.textSecondary,
                          ),
                    onTap: _canCheck(controller) ? _checkUpdates : null,
                  ),
                  if (showOpen) ...[
                    Divider(
                      height: BeanSpace.hairline,
                      thickness: BeanSpace.hairline,
                      indent: 60,
                      color: palette.border,
                    ),
                    ListTile(
                      key: const ValueKey('about-update-open'),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 2,
                      ),
                      title: Text(
                        '更新到 v${release.version}',
                        style: const TextStyle(fontSize: 16, height: 1.25),
                      ),
                      subtitle: Text(
                        release.sizeLabel,
                        style: TextStyle(
                          fontSize: 13,
                          color: palette.textSecondary,
                        ),
                      ),
                      trailing: Icon(
                        Icons.chevron_right_rounded,
                        size: 20,
                        color: palette.textSecondary,
                      ),
                      onTap: _openUpdatePage,
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 8),
            Text(
              _lastCheckLabel(controller),
              style: TextStyle(fontSize: 12, color: palette.textSecondary),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final palette = BeanPalette.of(context);

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
          '关于金豆',
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
          BeanCard(
            padding: EdgeInsets.zero,
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 24, 20, 20),
                  child: Column(
                    children: [
                      Container(
                        width: 64,
                        height: 64,
                        decoration: BoxDecoration(
                          color: BeanColors.gold.withValues(alpha: 0.16),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.savings_rounded,
                          size: 34,
                          color: BeanColors.goldDeep,
                        ),
                      ),
                      const SizedBox(height: 12),
                      const Text(
                        '金豆',
                        style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w600,
                          letterSpacing: -0.3,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '一颗圆豆子，肚子里存金币',
                        style: TextStyle(
                          fontSize: 13,
                          color: palette.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
                Divider(
                  height: BeanSpace.hairline,
                  thickness: BeanSpace.hairline,
                  color: palette.border,
                ),
                ListTile(
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
                  title: const Text(
                    '版本',
                    style: TextStyle(fontSize: 16, height: 1.25),
                  ),
                  trailing: Text(
                    _version?.fullLabel ?? '读取中…',
                    key: const ValueKey('about-version'),
                    style: TextStyle(fontSize: 15, color: palette.textSecondary),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: BeanSpace.section),
          if (widget.controller != null) ...[
            _updateSection(context),
            const SizedBox(height: BeanSpace.section),
          ],
          const SectionTitle('链接'),
          BeanCard(
            padding: EdgeInsets.zero,
            child: ListTile(
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              leading: Container(
                width: 29,
                height: 29,
                decoration: BoxDecoration(
                  color: const Color(0xFF24292F),
                  borderRadius: BorderRadius.circular(7),
                ),
                child: const Icon(
                  Icons.code_rounded,
                  size: 18,
                  color: Colors.white,
                ),
              ),
              title: const Text(
                'GitHub 仓库',
                style: TextStyle(fontSize: 16, height: 1.25),
              ),
              subtitle: Text(
                'mayapony/beancount',
                style: TextStyle(fontSize: 13, color: palette.textSecondary),
              ),
              trailing: Icon(
                Icons.chevron_right_rounded,
                size: 20,
                color: palette.textSecondary,
              ),
              onTap: _openRepository,
            ),
          ),
          const SizedBox(height: BeanSpace.section),
          Text(
            '检查更新只会向 GitHub 请求版本信息，不上传账本数据、设备标识或账号信息。',
            style: TextStyle(
              fontSize: 13,
              height: 1.5,
              color: palette.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}
