import 'package:flutter/material.dart';

import '../theme/tokens.dart';

/// 记账金豆 —— 全 App 的视觉锚点，中心停靠在底部导航凹槽里。
///
/// 注意：阴影必须画在**不被裁切**的父容器上。若把 boxShadow 写进 Material/Ink 的
/// decoration，阴影会被裁到 FAB 的矩形边界内，四角残留一圈被切断的暖色 —— 看起来
/// 就像加号四周有个方方块。
class BeanFab extends StatelessWidget {
  const BeanFab({super.key, required this.onPressed});

  final VoidCallback onPressed;

  static const double size = 62;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: DecoratedBox(
        // 阴影画在外层：圆形、不裁切
        decoration: const BoxDecoration(
          shape: BoxShape.circle,
          boxShadow: BeanShadow.bean,
        ),
        child: Material(
          color: Colors.transparent,
          shape: const CircleBorder(),
          clipBehavior: Clip.antiAlias,
          child: Ink(
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              gradient: BeanColors.goldGradient,
            ),
            child: InkWell(
              onTap: onPressed,
              customBorder: const CircleBorder(),
              child: const Center(
                child: Icon(Icons.add_rounded, color: Colors.white, size: 32),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
