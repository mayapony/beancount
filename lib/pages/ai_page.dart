import 'package:flutter/material.dart';

import '../theme/tokens.dart';
import '../widgets/common.dart';

class AiPage extends StatelessWidget {
  const AiPage({super.key});

  @override
  Widget build(BuildContext context) {
    final palette = BeanPalette.of(context);

    return SafeArea(
      bottom: false,
      child: ListView(
        padding: const EdgeInsets.only(bottom: 120),
        children: [
          const BeanPageHeader(
            title: 'AI 截图记账',
            subtitle: '截图丢进来，剩下的交给金豆',
          ),

          Padding(
            padding: const EdgeInsets.fromLTRB(
              BeanSpace.page,
              12,
              BeanSpace.page,
              0,
            ),
            child: BeanCard(
              padding: const EdgeInsets.all(24),
              child: Column(
                children: [
                  Container(
                    width: 88,
                    height: 88,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [
                          BeanColors.gold.withValues(alpha: 0.30),
                          BeanColors.gold.withValues(alpha: 0.08),
                        ],
                      ),
                    ),
                    child: const Icon(
                      Icons.photo_camera_rounded,
                      size: 40,
                      color: BeanColors.goldDeep,
                    ),
                  ),
                  const SizedBox(height: 18),
                  const Text(
                    '识别支付截图',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '微信 / 支付宝 / 银行短信截图都可以',
                    style: TextStyle(
                      fontSize: 13,
                      color: palette.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 20),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: () {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('截图识别将在 M7 实现')),
                        );
                      },
                      icon: const Icon(Icons.add_photo_alternate_rounded),
                      label: const Text('选择截图'),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    '图片仅用于本次识别，不会上传保存',
                    style: TextStyle(
                      fontSize: 11,
                      color: palette.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: BeanSpace.section),

          Padding(
            padding: const EdgeInsets.symmetric(horizontal: BeanSpace.page),
            child: BeanCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SectionTitle('怎么工作'),
                  _Step(
                    index: 1,
                    title: '截图或拍照',
                    subtitle: '从相册选，或直接拍一张',
                  ),
                  const SizedBox(height: 14),
                  _Step(
                    index: 2,
                    title: '自动识别',
                    subtitle: '金额、商家、分类、时间一次抽全',
                  ),
                  const SizedBox(height: 14),
                  _Step(
                    index: 3,
                    title: '确认入账',
                    subtitle: '永远由你确认后才落库',
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Step extends StatelessWidget {
  const _Step({
    required this.index,
    required this.title,
    required this.subtitle,
  });

  final int index;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    final palette = BeanPalette.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 26,
          height: 26,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: BeanColors.gold.withValues(alpha: 0.14),
            shape: BoxShape.circle,
          ),
          child: Text(
            '$index',
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: BeanColors.goldDeep,
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                subtitle,
                style: TextStyle(fontSize: 12, color: palette.textSecondary),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
