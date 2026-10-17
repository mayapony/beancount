import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'tokens.dart';

/// 字号档位（果味方向）：大标题 34 / 标题 22 / 行标题 17 / 正文 15 / 辅助 13 / 标签 11。
/// 全部带负字距 —— iOS 的字距比 Material 紧，这一条对「像不像原生」影响极大。
TextTheme _beanTextTheme(TextTheme base, Color onSurface, Color secondary) {
  return base.copyWith(
    displaySmall: TextStyle(
      fontSize: 34,
      height: 1.12,
      fontWeight: FontWeight.w700,
      letterSpacing: -0.6,
      color: onSurface,
    ),
    headlineSmall: TextStyle(
      fontSize: 22,
      height: 1.2,
      fontWeight: FontWeight.w700,
      letterSpacing: -0.4,
      color: onSurface,
    ),
    titleMedium: TextStyle(
      fontSize: 17,
      height: 1.3,
      fontWeight: FontWeight.w600,
      letterSpacing: -0.2,
      color: onSurface,
    ),
    bodyLarge: TextStyle(
      fontSize: 17,
      height: 1.35,
      fontWeight: FontWeight.w400,
      letterSpacing: -0.2,
      color: onSurface,
    ),
    bodyMedium: TextStyle(
      fontSize: 15,
      height: 1.35,
      fontWeight: FontWeight.w400,
      color: onSurface,
    ),
    bodySmall: TextStyle(
      fontSize: 13,
      height: 1.35,
      fontWeight: FontWeight.w400,
      color: secondary,
    ),
    labelSmall: TextStyle(
      fontSize: 11,
      height: 1.3,
      fontWeight: FontWeight.w400,
      color: secondary,
    ),
  );
}

/// 由 token 构建的 Material 3 主题。
ThemeData buildBeanTheme(Brightness brightness) {
  final dark = brightness == Brightness.dark;
  final bg = dark ? BeanColors.bgDark : BeanColors.bgLight;
  final surface = dark ? BeanColors.surfaceDark : BeanColors.surfaceLight;
  final onSurface = dark ? BeanColors.textDark : BeanColors.textLight;
  final secondaryText =
      dark ? BeanColors.textSecondaryDark : BeanColors.textSecondaryLight;
  final border = dark ? BeanColors.borderDark : BeanColors.borderLight;

  // iOS 上把字族切到引擎映射的 SF；Android / Web 保持系统默认（会走 MiSans / 思源）
  final fontFamily = defaultTargetPlatform == TargetPlatform.iOS
      ? 'CupertinoSystemText'
      : null;

  final scheme = ColorScheme(
    brightness: brightness,
    primary: BeanColors.goldDeep,
    onPrimary: Colors.white,
    primaryContainer: dark ? BeanColors.goldDeep : const Color(0xFFFEF3C7),
    onPrimaryContainer: dark ? Colors.white : const Color(0xFF78350F),
    secondary: BeanColors.beanGreenDeep,
    onSecondary: Colors.white,
    secondaryContainer:
        dark ? const Color(0xFF14532D) : const Color(0xFFDCFCE7),
    onSecondaryContainer:
        dark ? const Color(0xFFBBF7D0) : const Color(0xFF14532D),
    error: BeanColors.alertRed,
    onError: Colors.white,
    surface: surface,
    onSurface: onSurface,
    surfaceContainerHighest:
        dark ? const Color(0xFF2E2925) : const Color(0xFFF5F1EA),
    outline: border,
  );

  final base = ThemeData(
    useMaterial3: true,
    brightness: brightness,
    colorScheme: scheme,
    scaffoldBackgroundColor: bg,
  );

  final scale = _beanTextTheme(base.textTheme, onSurface, secondaryText);
  final textTheme =
      fontFamily == null ? scale : scale.apply(fontFamily: fontFamily);

  final rounded = RoundedRectangleBorder(
    borderRadius: BorderRadius.circular(BeanRadius.button),
  );

  return base.copyWith(
    extensions: [
      dark ? BeanPalette.dark(onSurface) : BeanPalette.light(onSurface),
    ],
    textTheme: textTheme,
    // 页面转场统一走 iOS 的横向推入 + 手滑返回（果味最容易感知的一层）
    pageTransitionsTheme: const PageTransitionsTheme(
      builders: {
        TargetPlatform.android: CupertinoPageTransitionsBuilder(),
        TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
        TargetPlatform.windows: CupertinoPageTransitionsBuilder(),
        TargetPlatform.macOS: CupertinoPageTransitionsBuilder(),
      },
    ),
    appBarTheme: AppBarTheme(
      backgroundColor: bg,
      foregroundColor: onSurface,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      surfaceTintColor: Colors.transparent,
    ),
    dividerTheme: DividerThemeData(color: border, thickness: 1, space: 1),
    iconTheme: IconThemeData(color: onSurface),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: BeanColors.goldDeep,
        foregroundColor: Colors.white,
        minimumSize: const Size(0, 48),
        padding: const EdgeInsets.symmetric(horizontal: 20),
        shape: rounded,
        textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: BeanColors.goldDeep,
        textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: onSurface,
        minimumSize: const Size(0, 48),
        side: BorderSide(color: border),
        shape: rounded,
        textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: surface,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      hintStyle: TextStyle(color: secondaryText, fontSize: 15),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(BeanRadius.input),
        borderSide: BorderSide(color: border),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(BeanRadius.input),
        borderSide: BorderSide(color: border),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(BeanRadius.input),
        borderSide: const BorderSide(color: BeanColors.gold, width: 1.5),
      ),
    ),
    bottomAppBarTheme: BottomAppBarTheme(color: surface, elevation: 0),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: onSurface,
      contentTextStyle: TextStyle(color: bg, fontSize: 14),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(BeanRadius.button),
      ),
    ),
    listTileTheme: ListTileThemeData(
      iconColor: secondaryText,
      textColor: onSurface,
    ),
  );
}
