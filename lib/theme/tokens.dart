import 'package:flutter/material.dart';

/// 金豆设计 token —— 完整规范见 docs/DESIGN.md。
///
/// 铁律：金色是点缀色，占屏 ≤10%；支出用默认文字色 + 负号，红只留给警示。
abstract final class BeanColors {
  // ── 品牌 ──────────────────────────────────────────────
  static const gold = Color(0xFFF59E0B);
  static const goldDeep = Color(0xFFB45309);
  static const goldLight = Color(0xFFFBBF24);
  static const goldDark = Color(0xFFD97706);
  static const beanGreen = Color(0xFF16A34A);
  static const beanGreenDeep = Color(0xFF15803D);
  static const alertRed = Color(0xFFE11D48);
  static const alertRedDeep = Color(0xFFBE123C);

  static const goldGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [goldLight, goldDark],
  );

  // ── 中性 · 亮（暖米白） ────────────────────────────────
  static const bgLight = Color(0xFFFAF7F2);
  static const surfaceLight = Color(0xFFFFFFFF);
  static const textLight = Color(0xFF1C1917);
  static const textSecondaryLight = Color(0xFF78716C);
  static const borderLight = Color(0xFFE7E5E4);

  // ── 中性 · 暗（暖黑） ─────────────────────────────────
  static const bgDark = Color(0xFF161311);
  static const surfaceDark = Color(0xFF24201C);
  static const textDark = Color(0xFFF5F5F4);
  static const textSecondaryDark = Color(0xFFA8A29E);
  static const borderDark = Color(0xFF3D3733);

  // ── 分类色板（12 色） ─────────────────────────────────
  static const categories = <Color>[
    Color(0xFFF59E0B), // 餐饮
    Color(0xFF3B82F6), // 交通
    Color(0xFFEC4899), // 购物
    Color(0xFF8B5CF6), // 娱乐
    Color(0xFF14B8A6), // 居家
    Color(0xFFEF4444), // 医疗
    Color(0xFF6366F1), // 教育
    Color(0xFF06B6D4), // 旅行
    Color(0xFF22C55E), // 运动
    Color(0xFF64748B), // 数码
    Color(0xFFF97316), // 宠物
    Color(0xFF94A3B8), // 其他
  ];

  static const categoryNames = <String>[
    '餐饮', '交通', '购物', '娱乐', '居家', '医疗',
    '教育', '旅行', '运动', '数码', '宠物', '其他',
  ];
}

abstract final class BeanRadius {
  static const card = 18.0;
  static const button = 14.0;
  static const input = 14.0;
  static const chip = 999.0;
}

abstract final class BeanSpace {
  static const page = 16.0;
  static const card = 16.0;
  static const section = 24.0;
  static const row = 64.0;
}

abstract final class BeanShadow {
  /// Soft UI：两层柔和阴影（比扁平有层次，比拟物克制）
  static const soft = <BoxShadow>[
    BoxShadow(color: Color(0x0A1C1917), offset: Offset(0, 1), blurRadius: 2),
    BoxShadow(color: Color(0x0F1C1917), offset: Offset(0, 4), blurRadius: 12),
  ];

  /// 金豆 FAB 的暖色投影
  static const bean = <BoxShadow>[
    BoxShadow(color: Color(0x40D97706), offset: Offset(0, 6), blurRadius: 16),
  ];
}

/// 语义色扩展：随明暗主题解析。
@immutable
class BeanPalette extends ThemeExtension<BeanPalette> {
  const BeanPalette({
    required this.income,
    required this.expense,
    required this.transfer,
    required this.alert,
    required this.gold,
    required this.goldDeep,
    required this.surface,
    required this.border,
    required this.textSecondary,
  });

  final Color income;
  final Color expense;
  final Color transfer;
  final Color alert;
  final Color gold;
  final Color goldDeep;
  final Color surface;
  final Color border;
  final Color textSecondary;

  /// 设计约定：支出 = 默认文字色（不刷红），红色只用于警示。
  factory BeanPalette.light(Color onSurface) => BeanPalette(
        income: BeanColors.beanGreenDeep,
        expense: onSurface,
        transfer: BeanColors.textSecondaryLight,
        alert: BeanColors.alertRedDeep,
        gold: BeanColors.gold,
        goldDeep: BeanColors.goldDeep,
        surface: BeanColors.surfaceLight,
        border: BeanColors.borderLight,
        textSecondary: BeanColors.textSecondaryLight,
      );

  factory BeanPalette.dark(Color onSurface) => BeanPalette(
        income: const Color(0xFF4ADE80),
        expense: onSurface,
        transfer: BeanColors.textSecondaryDark,
        alert: const Color(0xFFFB7185),
        gold: BeanColors.gold,
        goldDeep: BeanColors.goldLight,
        surface: BeanColors.surfaceDark,
        border: BeanColors.borderDark,
        textSecondary: BeanColors.textSecondaryDark,
      );

  static BeanPalette of(BuildContext context) =>
      Theme.of(context).extension<BeanPalette>()!;

  @override
  BeanPalette copyWith({
    Color? income,
    Color? expense,
    Color? transfer,
    Color? alert,
    Color? gold,
    Color? goldDeep,
    Color? surface,
    Color? border,
    Color? textSecondary,
  }) {
    return BeanPalette(
      income: income ?? this.income,
      expense: expense ?? this.expense,
      transfer: transfer ?? this.transfer,
      alert: alert ?? this.alert,
      gold: gold ?? this.gold,
      goldDeep: goldDeep ?? this.goldDeep,
      surface: surface ?? this.surface,
      border: border ?? this.border,
      textSecondary: textSecondary ?? this.textSecondary,
    );
  }

  @override
  BeanPalette lerp(ThemeExtension<BeanPalette>? other, double t) {
    if (other is! BeanPalette) return this;
    return BeanPalette(
      income: Color.lerp(income, other.income, t)!,
      expense: Color.lerp(expense, other.expense, t)!,
      transfer: Color.lerp(transfer, other.transfer, t)!,
      alert: Color.lerp(alert, other.alert, t)!,
      gold: Color.lerp(gold, other.gold, t)!,
      goldDeep: Color.lerp(goldDeep, other.goldDeep, t)!,
      surface: Color.lerp(surface, other.surface, t)!,
      border: Color.lerp(border, other.border, t)!,
      textSecondary: Color.lerp(textSecondary, other.textSecondary, t)!,
    );
  }
}
