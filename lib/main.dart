import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'pages/shell.dart';
import 'theme/app_theme.dart';

void main() => runApp(const BeanApp());

class BeanApp extends StatelessWidget {
  const BeanApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '金豆',
      debugShowCheckedModeBanner: false,
      theme: buildBeanTheme(Brightness.light),
      darkTheme: buildBeanTheme(Brightness.dark),
      themeMode: ThemeMode.system,
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const [
        Locale('zh', 'CN'),
        Locale('en'),
      ],
      builder: (context, child) {
        final isDark = Theme.of(context).brightness == Brightness.dark;
        final base =
            isDark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark;
        return AnnotatedRegion<SystemUiOverlayStyle>(
          value: base.copyWith(
            statusBarColor: Colors.transparent,
            systemNavigationBarColor: Colors.transparent,
          ),
          child: child!,
        );
      },
      home: const ShellPage(),
    );
  }
}
