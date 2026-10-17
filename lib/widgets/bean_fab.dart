import 'package:flutter/material.dart';

import '../theme/tokens.dart';

/// 记账金豆 —— 全 App 的视觉锚点，中心停靠在底部导航凹槽里。
class BeanFab extends StatelessWidget {
  const BeanFab({super.key, required this.onPressed});

  final VoidCallback onPressed;

  static const double size = 62;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: Material(
        color: Colors.transparent,
        shape: const CircleBorder(),
        child: Ink(
          decoration: const BoxDecoration(
            shape: BoxShape.circle,
            gradient: BeanColors.goldGradient,
            boxShadow: BeanShadow.bean,
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
    );
  }
}
