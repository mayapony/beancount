// 设计评审用的截图工具（不是断言测试）：
//   flutter test test/tools/capture_screens_test.dart
// 在 docs/review/shots/ 下生成 402×874 逻辑分辨率、2x 的 PNG。
//
// 为什么需要它：`flutter test` 默认用 Ahem 字体（方块字），无法用于排版评审，
// 所以这里手动加载 FontManifest（MaterialIcons）与系统中文字体 Noto Sans SC；
// 截图必须包在 `tester.runAsync` 里，否则引擎回调在假时钟下永远不返回。
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:bean_count/data/db/app_database.dart';
import 'package:bean_count/data/db/connection.dart';
import 'package:bean_count/data/repositories/attachment_repository.dart';
import 'package:bean_count/pages/import_page.dart';
import 'package:bean_count/pages/shell.dart';
import 'package:bean_count/data/repositories/account_repository.dart';
import 'package:bean_count/data/repositories/category_repository.dart';
import 'package:bean_count/data/repositories/transaction_repository.dart';
import 'package:bean_count/services/import/import_service.dart';
import 'package:bean_count/theme/app_theme.dart';
import 'package:bean_count/widgets/quick_entry_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

import 'demo_seed.dart';

const _cjkFontPath = r'C:\Windows\Fonts\NotoSansSC-VF.ttf';
const _outDir = 'docs/review/shots';

/// 截图脚本共用一份内存库：分类/种子真实存在，但不落磁盘、不碰 path_provider。
late AppDatabase _db;
late AttachmentRepository _attachments;
late Directory _attachmentDir;

Future<void> _loadBundledFonts() async {
  final manifest = json.decode(
    await rootBundle.loadString('FontManifest.json'),
  ) as List<dynamic>;
  for (final family in manifest) {
    final map = family as Map<String, dynamic>;
    final loader = FontLoader(map['family'] as String);
    for (final font in (map['fonts'] as List<dynamic>)) {
      loader.addFont(rootBundle.load((font as Map)['asset'] as String));
    }
    await loader.load();
  }
}

Future<void> _loadCjkFont() async {
  final file = File(_cjkFontPath);
  if (!file.existsSync()) return;
  final bytes = file.readAsBytesSync();
  final loader = FontLoader('NotoSansSC')
    ..addFont(Future.value(ByteData.view(bytes.buffer)));
  await loader.load();
}

ThemeData _theme([Brightness brightness = Brightness.light]) {
  final base = buildBeanTheme(brightness);
  // 按钮样式在主题里写死了 fontSize/weight 但没带字族，测试环境会退回 Ahem（方块字）；
  // 这里统一补上中文字族，截图里才不会出现豆腐块。
  const labelStyle = TextStyle(
    fontFamily: 'NotoSansSC',
    fontSize: 15,
    fontWeight: FontWeight.w600,
  );
  return base.copyWith(
    textTheme: base.textTheme.apply(fontFamily: 'NotoSansSC'),
    primaryTextTheme: base.primaryTextTheme.apply(fontFamily: 'NotoSansSC'),
    filledButtonTheme: FilledButtonThemeData(
      style: base.filledButtonTheme.style?.copyWith(
        textStyle: const WidgetStatePropertyAll(labelStyle),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: base.textButtonTheme.style?.copyWith(
        textStyle: const WidgetStatePropertyAll(labelStyle),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: base.outlinedButtonTheme.style?.copyWith(
        textStyle: const WidgetStatePropertyAll(labelStyle),
      ),
    ),
  );
}

Future<void> _pumpApp(
  WidgetTester tester, {
  Brightness brightness = Brightness.light,
  Size size = const Size(402, 874),
}) async {
  tester.view.physicalSize = size * 3;
  tester.view.devicePixelRatio = 3;
  tester.view.padding = const FakeViewPadding(top: 47 * 3, bottom: 34 * 3);
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPadding);

  await tester.pumpWidget(
    RepaintBoundary(
      key: const ValueKey('screen'),
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: _theme(brightness),
        // 时间滚轮等 Cupertino 控件跟 App 一样走中文
        locale: const Locale('zh', 'CN'),
        supportedLocales: const [Locale('zh', 'CN'), Locale('en')],
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        home: ShellPage(
          database: _db,
          attachmentRepository: _attachments,
        ),
      ),
    ),
  );
  await _settle(tester);
}

/// 不用 pumpAndSettle：有持续动画时它会把假时钟拖到超时。
Future<void> _settle(WidgetTester tester) async {
  await tester.pump();
  for (var i = 0; i < 5; i++) {
    await tester.pump(const Duration(milliseconds: 200));
  }
}

Future<void> _shot(WidgetTester tester, String name) async {
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(const ValueKey('screen')),
  );
  await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 2);
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    Directory(_outDir).createSync(recursive: true);
    File('$_outDir/$name.png').writeAsBytesSync(data!.buffer.asUint8List());
    image.dispose();
  });
}

Finder _inSheet(Finder matching) => find.descendant(
      of: find.byType(QuickEntrySheet),
      matching: matching,
    );

void main() {
  setUpAll(() async {
    _db = AppDatabase(openInMemoryConnection());
    _attachmentDir = Directory.systemTemp.createTempSync('bean_shots');
    _attachments = AttachmentRepository(_db, directory: _attachmentDir);
    await seedDemoLedger(_db, attachments: _attachments);
    await _loadBundledFonts();
    await _loadCjkFont();
  });

  tearDownAll(() async {
    await _db.close();
    if (_attachmentDir.existsSync()) _attachmentDir.deleteSync(recursive: true);
  });

  testWidgets('shot: entry flow', (tester) async {
    await _pumpApp(tester);

    await tester.tap(find.byIcon(Icons.add_rounded));
    await _settle(tester);
    await _shot(tester, '01-entry-default');

    for (final key in ['3', '8', '.', '5']) {
      await tester.tap(_inSheet(find.text(key)).last);
      await tester.pump();
    }
    await tester.tap(_inSheet(find.text('+')).last);
    await _settle(tester);
    await _shot(tester, '02-entry-operator');

    await tester.tap(_inSheet(find.text('收入')));
    await _settle(tester);
    await _shot(tester, '03-entry-income');

    // 回到支出并取消待计算，给备注/标签留一个干净的画面
    await tester.tap(_inSheet(find.text('支出')));
    await tester.tap(_inSheet(find.text('+')).last);
    await _settle(tester);

    await tester.tap(find.text('点击填写备注'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField), '和家人吃晚饭');
    await tester.tap(find.text('确定'));
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.sell_outlined));
    await tester.pumpAndSettle();
    await tester.tap(find.text('聚餐'));
    await tester.pump();
    await tester.tap(find.text('报销'));
    await tester.pump();
    await tester.tap(find.text('确定'));
    await tester.pumpAndSettle();

    await tester.tap(_inSheet(find.text('1')).last);
    await tester.tap(_inSheet(find.text('2')).last);
    await _settle(tester);
    await _shot(tester, '04-entry-note');

    // 再记：确认落在备注行（不是被面板挡住的 SnackBar）
    await tester.tap(_inSheet(find.text('再记')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await _shot(tester, '05-entry-toast');
  });

  testWidgets('shot: dark mode', (tester) async {
    await _pumpApp(tester, brightness: Brightness.dark);
    await _shot(tester, '15-home-dark');

    await tester.tap(find.byIcon(Icons.add_rounded));
    await _settle(tester);
    await _shot(tester, '06-entry-dark');
  });

  // 小屏回归：iPhone SE 尺寸下键盘必须仍然可见（分类区内部滚动，不许溢出）
  testWidgets('shot: small screen', (tester) async {
    await _pumpApp(tester, size: const Size(375, 667));
    await tester.tap(find.byIcon(Icons.add_rounded));
    await _settle(tester);
    await _shot(tester, '07-entry-small');
  });

  testWidgets('shot: account + time pickers', (tester) async {
    await _pumpApp(tester);
    await tester.tap(find.byIcon(Icons.add_rounded));
    await _settle(tester);

    await tester.tap(_inSheet(find.byIcon(Icons.account_balance_wallet_rounded)));
    await _settle(tester);
    await _shot(tester, '08-entry-account');

    await tester.tap(find.byTooltip('关闭').last);
    await _settle(tester);

    await tester.tap(_inSheet(find.textContaining('今天')));
    await _settle(tester);
    await _shot(tester, '09-entry-time');
  });

  // 四个 Tab：标题替换 + 分组列表 + 发丝线的整体走查
  testWidgets('shot: four tabs', (tester) async {
    await tester.runAsync(
      () => resetDemoLedger(_db, attachments: _attachments),
    );
    await _pumpApp(tester);
    await _shot(tester, '10-home-current');

    await tester.tap(find.byIcon(Icons.donut_small_rounded));
    await _settle(tester);
    await _shot(tester, '12-tab-insights');

    await tester.tap(find.byIcon(Icons.account_balance_wallet_rounded));
    await _settle(tester);
    await _shot(tester, '13-tab-assets');

    await tester.tap(find.byIcon(Icons.settings_rounded));
    await _settle(tester);
    await _shot(tester, '14-tab-settings');
  });

  // 滚到底：确认最后一条内容不会被底栏压住（底部 padding 够不够）

  // 导入预览：评审"数字是否一眼看懂"
  testWidgets('shot: import preview', (tester) async {
    final categories = CategoryRepository(_db);
    final accounts = AccountRepository(_db);
    final transactions = TransactionRepository(_db);
    final service = ImportService(
      db: _db,
      categories: categories,
      accounts: accounts,
      transactions: transactions,
      attachments: _attachments,
    );
    final bytes = File('test/fixtures/beecount_sample.csv').readAsBytesSync();

    tester.view.physicalSize = const Size(402, 874) * 3;
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      RepaintBoundary(
        key: const ValueKey('screen'),
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: _theme(),
          home: ImportPage(
            service: service,
            initialBytes: bytes,
            initialName: 'beecount_sample.csv',
          ),
        ),
      ),
    );
    await _settle(tester);
    await _settle(tester);
    await _shot(tester, '20-import-preview');
  });

  testWidgets('shot: scrolled to bottom', (tester) async {
    await tester.runAsync(
      () => resetDemoLedger(_db, attachments: _attachments),
    );
    await _pumpApp(tester);
    await tester.tap(find.byIcon(Icons.donut_small_rounded));
    await _settle(tester);
    await tester.dragFrom(const Offset(200, 600), const Offset(0, -1200));
    await _settle(tester);
    await _shot(tester, '16-insights-bottom');
  });
}
