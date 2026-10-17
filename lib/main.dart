import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'data/db/app_database.dart';
import 'data/db/connection.dart';
import 'data/repositories/lock_repository.dart';
import 'pages/shell.dart';
import 'theme/app_theme.dart';
import 'widgets/lock_gate.dart';

void main() => runApp(const BeanApp());

/// 全 App 只有这一个数据库实例：应用锁与账本共享它。
final AppDatabase _db = AppDatabase(openDatabaseConnection());

class BeanApp extends StatelessWidget {
  const BeanApp({super.key, this.database, this.lockRepository});

  /// 测试注入用；为空时用真实的文件库。
  final AppDatabase? database;
  final LockRepository? lockRepository;

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
      home: LockGate(
        repository: lockRepository ?? LockRepository(database ?? _db),
        child: ShellPage(database: database ?? _db),
      ),
    );
  }
}
