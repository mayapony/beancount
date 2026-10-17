import 'package:flutter/material.dart';

import '../theme/tokens.dart';
import '../widgets/common.dart';
import 'design_showcase_page.dart';

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final palette = BeanPalette.of(context);

    return SafeArea(
      bottom: false,
      child: ListView(
        padding: const EdgeInsets.only(bottom: 120),
        children: [
          const BeanPageHeader(title: '设置'),

          const SizedBox(height: 8),

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
                    icon: Icons.swap_vert_rounded,
                    color: const Color(0xFF64748B),
                    title: '导入 / 导出',
                    subtitle: 'CSV / Excel / 支付宝 / 微信账单',
                    trailing: 'M8',
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
        height: 1,
        indent: 64,
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
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, size: 19, color: color),
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
                    fontWeight: FontWeight.w500,
                  ),
                ),
                if (subtitle != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    subtitle!,
                    style: TextStyle(
                      fontSize: 11.5,
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
              style: TextStyle(fontSize: 12, color: palette.textSecondary),
            ),
          if (onTap != null) ...[
            const SizedBox(width: 4),
            Icon(
              Icons.chevron_right_rounded,
              size: 18,
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
