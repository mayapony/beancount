import 'package:flutter/material.dart';

import 'tokens.dart';

/// 由 token 构建的 Material 3 主题。
ThemeData buildBeanTheme(Brightness brightness) {
  final dark = brightness == Brightness.dark;
  final bg = dark ? BeanColors.bgDark : BeanColors.bgLight;
  final surface = dark ? BeanColors.surfaceDark : BeanColors.surfaceLight;
  final onSurface = dark ? BeanColors.textDark : BeanColors.textLight;
  final secondaryText =
      dark ? BeanColors.textSecondaryDark : BeanColors.textSecondaryLight;
  final border = dark ? BeanColors.borderDark : BeanColors.borderLight;

  final scheme = ColorScheme(
    brightness: brightness,
    primary: BeanColors.goldDeep,
    onPrimary: Colors.white,
    primaryContainer: dark ? BeanColors.goldDeep : const Color(0xFFFEF3C7),
    onPrimaryContainer: dark ? Colors.white : const Color(0xFF78350F),
    secondary: BeanColors.beanGreenDeep,
    onSecondary: Colors.white,
    secondaryContainer: dark ? const Color(0xFF14532D) : const Color(0xFFDCFCE7),
    onSecondaryContainer:
        dark ? const Color(0xFFBBF7D0) : const Color(0xFF14532D),
    error: BeanColors.alertRed,
    onError: Colors.white,
    surface: surface,
    onSurface: onSurface,
    surfaceContainerHighest: dark ? const Color(0xFF2E2925) : const Color(0xFFF5F1EA),
    outline: border,
  );

  final base = ThemeData(
    useMaterial3: true,
    brightness: brightness,
    colorScheme: scheme,
    scaffoldBackgroundColor: bg,
  );

  final rounded = RoundedRectangleBorder(
    borderRadius: BorderRadius.circular(BeanRadius.button),
  );

  return base.copyWith(
    extensions: [
      dark ? BeanPalette.dark(onSurface) : BeanPalette.light(onSurface),
    ],
    textTheme: base.textTheme.apply(bodyColor: onSurface, displayColor: onSurface),
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
