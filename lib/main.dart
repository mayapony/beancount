import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'data/db/app_database.dart';
import 'data/db/connection.dart';
import 'data/repositories/app_state_repository.dart';
import 'data/repositories/lock_repository.dart';
import 'data/repositories/theme_repository.dart';
import 'pages/shell.dart';
import 'services/update/app_version.dart';
import 'services/update/update_controller.dart';
import 'services/update/update_services.dart';
import 'theme/app_theme.dart';
import 'theme/theme_controller.dart';
import 'widgets/lock_gate.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // 先把已保存的主题读出来再 runApp：首帧就是正确的亮/暗，不会闪一下
  final controller = ThemeController(repository: ThemeRepository(_db));
  await controller.load();

  final version = await loadAppVersion();
  final update = createUpdateController(
    appState: AppStateRepository(_db),
    version: version,
  );

  runApp(
    BeanApp(themeController: controller, updateController: update),
  );
}

/// 全 App 只有这一个数据库实例：应用锁与账本共享它。
final AppDatabase _db = AppDatabase(openDatabaseConnection());

class BeanApp extends StatefulWidget {
  const BeanApp({
    super.key,
    this.database,
    this.lockRepository,
    this.themeController,
    this.updateController,
  });

  /// 测试注入用；为空时用真实的文件库。
  final AppDatabase? database;
  final LockRepository? lockRepository;

  /// 主题控制器（main 注入）；测试不传时内部建一个跟随系统的。
  final ThemeController? themeController;

  /// 更新控制器（main 注入）；测试不传时不做更新检查。
  final UpdateController? updateController;

  @override
  State<BeanApp> createState() => _BeanAppState();
}

class _BeanAppState extends State<BeanApp> {
  late final ThemeController _controller = widget.themeController ??
      ThemeController(repository: ThemeRepository(widget.database ?? _db));

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _controller,
      builder: (context, _) => _buildApp(),
    );
  }

  Widget _buildApp() {
    return MaterialApp(
      title: '金豆',
      debugShowCheckedModeBanner: false,
      theme: buildBeanTheme(Brightness.light),
      darkTheme: buildBeanTheme(Brightness.dark),
      themeMode: _controller.mode,
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
        repository:
            widget.lockRepository ?? LockRepository(widget.database ?? _db),
        child: ShellPage(
          database: widget.database ?? _db,
          themeController: _controller,
          updateController: widget.updateController,
        ),
      ),
    );
  }
}
