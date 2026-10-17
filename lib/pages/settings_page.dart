import 'package:flutter/material.dart';

import '../data/repositories/account_repository.dart';
import '../data/repositories/category_repository.dart';
import '../services/export/export_service.dart';
import '../services/import/import_service.dart';
import '../theme/tokens.dart';
import '../widgets/common.dart';
import 'accounts_page.dart';
import 'categories_page.dart';
import 'design_showcase_page.dart';
import 'export_page.dart';
import 'import_page.dart';

class SettingsPage extends StatelessWidget {
  const SettingsPage({
    super.key,
    required this.importer,
    required this.exporter,
    required this.categories,
    required this.accounts,
  });

  final ImportService importer;
  final ExportService exporter;
  final CategoryRepository categories;
  final AccountRepository accounts;

  @override
  Widget build(BuildContext context) {
    final palette = BeanPalette.of(context);

    return SafeArea(
      bottom: false,
      child: ListView(
        padding: const EdgeInsets.only(bottom: 120),
        children: [
          // 设置是"入口列表"，没有数字可当锚点，所以标题保留（只是换成大标题）
          const BeanLargeTitle(title: '设置'),

          // ── 外观 ──────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: BeanSpace.page),
            child: BeanCard(
              padding: EdgeInsets.zero,
              child: Column(
                children: [
                  _SettingTile(
                    icon: Icons.palette_rounded,
                    color: BeanColors.gold,
                    title: '设计规范 Demo',
                    subtitle: '色彩 / 字阶 / 组件 / 暗色，用于敲定视觉',
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => const DesignShowcasePage(),
                      ),
                    ),
                  ),
                  _divider(palette),
                  _SettingTile(
                    icon: Icons.brightness_6_rounded,
                    color: const Color(0xFF8B5CF6),
                    title: '主题',
                    trailing: '跟随系统',
                  ),
                  _divider(palette),
                  _SettingTile(
                    icon: Icons.lock_outline_rounded,
                    color: const Color(0xFF3B82F6),
                    title: '应用锁',
                    trailing: 'M9',
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: BeanSpace.section),

          // ── 截图记账（自动触发，无需入口） ────────────────
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: BeanSpace.page),
            child: BeanCard(
              padding: EdgeInsets.zero,
              child: Column(
                children: [
                  _SettingTile(
                    icon: Icons.auto_awesome_rounded,
                    color: BeanColors.beanGreen,
                    title: '截图记账',
                    subtitle: '截屏后自动识别，确认即入账',
                    trailing: '自动',
                  ),
                  _divider(palette),
                  _SettingTile(
                    icon: Icons.photo_library_rounded,
                    color: const Color(0xFF06B6D4),
                    title: '识别范围',
                    trailing: '支付 / 账单截图',
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: BeanSpace.section),

          // ── 数据 ──────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: BeanSpace.page),
            child: BeanCard(
              padding: EdgeInsets.zero,
              child: Column(
                children: [
                  _SettingTile(
                    icon: Icons.category_rounded,
                    color: BeanColors.beanGreen,
                    title: '分类',
                    subtitle: '新建、改名、排序与删除（删除可迁移）',
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => CategoriesPage(repository: categories),
                      ),
                    ),
                  ),
                  _divider(palette),
                  _SettingTile(
                    icon: Icons.account_balance_wallet_rounded,
                    color: const Color(0xFF0EA5E9),
                    title: '账户',
                    subtitle: '名称、类型与期初余额',
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => AccountsPage(repository: accounts),
                      ),
                    ),
                  ),
                  _divider(palette),
                  _SettingTile(
                    icon: Icons.move_to_inbox_rounded,
                    color: BeanColors.goldDeep,
                    title: '从 BeeCount 导入',
                    subtitle: '支持完整备份 zip（含图片）与 CSV',
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => ImportPage(service: importer),
                      ),
                    ),
                  ),
                  _divider(palette),
                  _SettingTile(
                    icon: Icons.swap_vert_rounded,
                    color: const Color(0xFF64748B),
                    title: '导出',
                    subtitle: 'CSV 或含图片的完整备份',
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => ExportPage(service: exporter),
                      ),
                    ),
                  ),
                  _divider(palette),
                  _SettingTile(
                    icon: Icons.cloud_outlined,
                    color: const Color(0xFF14B8A6),
                    title: '云同步',
                    subtitle: 'S3 同步（后续版本）',
                    trailing: 'Backlog',
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: BeanSpace.section),

          // ── 关于 ──────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: BeanSpace.page),
            child: BeanCard(
              padding: EdgeInsets.zero,
              child: Column(
                children: [
                  _SettingTile(
                    icon: Icons.info_outline_rounded,
                    color: BeanColors.gold,
                    title: '关于金豆',
                    subtitle: '一颗圆豆子，肚子里存金币',
                    trailing: 'v0.0.1',
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 24),
          Center(
            child: Text(
              '金豆 · 种豆得钱',
              style: TextStyle(fontSize: 11, color: palette.textSecondary),
            ),
          ),
        ],
      ),
    );
  }

  Widget _divider(BeanPalette palette) => Divider(
        height: BeanSpace.hairline,
        thickness: BeanSpace.hairline,
        indent: 60,
        color: palette.border,
      );
}

class _SettingTile extends StatelessWidget {
  const _SettingTile({
    required this.icon,
    required this.color,
    required this.title,
    this.subtitle,
    this.trailing,
    this.onTap,
  });

  final IconData icon;
  final Color color;
  final String title;
  final String? subtitle;
  final String? trailing;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final palette = BeanPalette.of(context);
    final content = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      child: Row(
        children: [
          // iOS 设置页语言：29 圆角方块 + 实色 + 白色字形
          Container(
            width: 29,
            height: 29,
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(7),
            ),
            child: Icon(icon, size: 18, color: Colors.white),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 17,
                    height: 1.25,
                    letterSpacing: -0.2,
                    fontWeight: FontWeight.w400,
                  ),
                ),
                if (subtitle != null) ...[
                  const SizedBox(height: 1),
                  Text(
                    subtitle!,
                    style: TextStyle(
                      fontSize: 13,
                      height: 1.2,
                      color: palette.textSecondary,
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (trailing != null)
            Text(
              trailing!,
              style: TextStyle(fontSize: 15, color: palette.textSecondary),
            ),
          if (onTap != null) ...[
            const SizedBox(width: 6),
            Icon(
              Icons.chevron_right_rounded,
              size: 20,
              color: palette.textSecondary,
            ),
          ],
        ],
      ),
    );

    if (onTap == null) return content;
    return InkWell(onTap: onTap, child: content);
  }
}
