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

  // ── 中性 · 亮（分组列表底色：白卡片压在暖灰上，靠 0.5px 发丝线分隔） ──
  static const bgLight = Color(0xFFF5F1EA);
  static const surfaceLight = Color(0xFFFFFFFF);
  static const textLight = Color(0xFF1C1917);
  static const textSecondaryLight = Color(0xFF78716C);
  static const borderLight = Color(0xFFE4DED3);

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
    '餐饮',
    '交通',
    '购物',
    '娱乐',
    '居家',
    '医疗',
    '教育',
    '旅行',
    '运动',
    '数码',
    '宠物',
    '其他',
  ];

  /// 收入分类色板（6 色）：与支出色板同明度、不同色相，
  /// 避免"收入也用金色"造成语义混淆。
  static const incomeCategories = <Color>[
    Color(0xFF16A34A), // 工资
    Color(0xFFEAB308), // 奖金
    Color(0xFF0EA5E9), // 兼职
    Color(0xFF8B5CF6), // 理财
    Color(0xFFE11D48), // 红包
    Color(0xFF94A3B8), // 其他收入
  ];

  /// 图表用色：把分类色向表面色混合，降低饱和度，贴近暖金基调。
  static List<Color> softenedChartColors(Color surface) => [
        for (final c in categories) Color.lerp(c, surface, 0.28)!,
      ];
}

abstract final class BeanRadius {
  /// 分组卡片：iOS inset grouped list 的 10–12，这里取 14 兼顾大屏
  static const card = 14.0;
  static const button = 12.0;
  static const input = 14.0;
  static const chip = 999.0;
  static const sheet = 24.0;
}

abstract final class BeanSpace {
  /// 页面左右边距：20（iOS 常用 16–20，这里向大留白靠）
  static const page = 20.0;
  static const card = 16.0;
  static const section = 26.0;
  static const row = 56.0;

  /// 发丝线：iOS 分隔线 0.5pt
  static const hairline = 0.5;
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
///
/// `neutral` 是记账面板的"表面分层"补充色：面板白底上的键盘底座、输入框描边、
/// 未选中图标、禁用态。放在 palette 里而不是写死在组件，深色模式才能一起走。
@immutable
class BeanNeutral {
  const BeanNeutral({
    required this.sand,
    required this.raised,
    required this.track,
    required this.lineStrong,
    required this.iconNeutral,
    required this.disabledBg,
    required this.disabledFg,
    required this.handle,
  });

  /// 键盘底座 / 次表面：把"可点区域"从白色面板里分出来
  final Color sand;

  /// 分段控件轨道 / 滑块槽：比所在表面再深一档，白色胶囊才立得住。
  final Color track;

  /// 抬升面：砂色底座上的键帽 / 分段控件选中块。
  /// 亮色是白，暗色必须比底座**更亮**（暗色下"更暗 = 凹陷"）。
  final Color raised;

  /// 输入框（金额卡）描边，比 border 更实一点
  final Color lineStrong;

  /// 未选中分类图标（亮色 3.5:1，达图形元素 3:1）
  final Color iconNeutral;

  final Color disabledBg;
  final Color disabledFg;

  /// 拖拽条，暖灰，不用 Material 默认的冷灰 onSurfaceVariant
  final Color handle;

  factory BeanNeutral.light() => const BeanNeutral(
        sand: Color(0xFFF5F1EA),
        raised: Color(0xFFFFFFFF),
        track: Color(0xFFE9E3DA),
        lineStrong: Color(0xFFE2DBD0),
        iconNeutral: Color(0xFF8A7F72),
        disabledBg: Color(0xFFEDE7DD),
        disabledFg: Color(0xFF857B6C),
        handle: Color(0xFFDED7CB),
      );

  factory BeanNeutral.dark() => const BeanNeutral(
        sand: Color(0xFF2A2521),
        raised: Color(0xFF352F2A),
        track: Color(0xFF332D28),
        lineStrong: Color(0xFF45403A),
        iconNeutral: Color(0xFFB4AA9C),
        disabledBg: Color(0xFF2E2925),
        disabledFg: Color(0xFF8F8579),
        handle: Color(0xFF4A423A),
      );

  BeanNeutral lerp(BeanNeutral other, double t) => BeanNeutral(
        sand: Color.lerp(sand, other.sand, t)!,
        raised: Color.lerp(raised, other.raised, t)!,
        track: Color.lerp(track, other.track, t)!,
        lineStrong: Color.lerp(lineStrong, other.lineStrong, t)!,
        iconNeutral: Color.lerp(iconNeutral, other.iconNeutral, t)!,
        disabledBg: Color.lerp(disabledBg, other.disabledBg, t)!,
        disabledFg: Color.lerp(disabledFg, other.disabledFg, t)!,
        handle: Color.lerp(handle, other.handle, t)!,
      );
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
    required this.chartColors,
    required this.neutral,
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

  /// 记账面板的表面分层色（键盘底座 / 描边 / 禁用态）
  final BeanNeutral neutral;

  /// 图表专用的柔和分类色（不再直接使用高饱和品牌分类色）
  final List<Color> chartColors;

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
        chartColors: BeanColors.softenedChartColors(BeanColors.surfaceLight),
        neutral: BeanNeutral.light(),
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
        chartColors: BeanColors.softenedChartColors(BeanColors.surfaceDark),
        neutral: BeanNeutral.dark(),
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
    List<Color>? chartColors,
    BeanNeutral? neutral,
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
      chartColors: chartColors ?? this.chartColors,
      neutral: neutral ?? this.neutral,
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
      chartColors: [
        for (var i = 0; i < chartColors.length; i++)
          Color.lerp(
            chartColors[i],
            other.chartColors[i % other.chartColors.length],
            t,
          )!,
      ],
      neutral: neutral.lerp(other.neutral, t),
    );
  }
}
