import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/update/app_version.dart';
import '../theme/tokens.dart';
import '../widgets/common.dart';

/// 设置 →「关于金豆」：真实版本、仓库链接与更新隐私说明。
///
/// 版本只从平台包信息读取；读不到时显示「版本未知」，不写死任何数字。
class AboutPage extends StatefulWidget {
  const AboutPage({super.key, this.versionLoader});

  /// 测试注入；为空时走 [loadAppVersion]。
  final Future<AppVersion> Function()? versionLoader;

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
