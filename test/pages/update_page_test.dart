import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bean_count/pages/update_page.dart';
import 'package:bean_count/services/update/apk_installer.dart';
import 'package:bean_count/services/update/update_models.dart';
import 'package:bean_count/theme/app_theme.dart';

import '../support/update_fakes.dart';

void main() {
  late UpdateTestContext ctx;

  setUp(() async {
    ctx = await UpdateTestContext.create();
  });

  tearDown(() async {
    await ctx.close();
  });

  Future<void> pump(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: buildBeanTheme(Brightness.light),
        home: UpdatePage(controller: ctx.controller, autoStart: false),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('可更新时展示版本、体积、说明与下载入口', (tester) async {
    await ctx.makeAvailable();
    await pump(tester);

    expect(find.text('更新到 v1.0.2'), findsOneWidget);
    expect(find.text('金豆 v1.0.2'), findsOneWidget);
    expect(find.textContaining('47.9 MB'), findsOneWidget);
    expect(find.textContaining('应用内检查更新'), findsOneWidget);
    expect(find.byKey(const ValueKey('update-download')), findsOneWidget);
  });

  testWidgets('下载中显示进度与取消，完成后出现安装入口', (tester) async {
    await ctx.makeAvailable();
    ctx.downloader.hold = Completer<String>();
    await pump(tester);

    await tester.tap(find.byKey(const ValueKey('update-download')));
    await tester.pump();

    expect(find.byKey(const ValueKey('update-progress')), findsOneWidget);
    expect(find.text('10 B / 100 B'), findsOneWidget);
    expect(find.byKey(const ValueKey('update-cancel')), findsOneWidget);

    ctx.downloader.hold!.complete(ctx.downloader.path);
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('update-install')), findsOneWidget);
    expect(find.text('下载完成，可以安装'), findsOneWidget);
  });

  testWidgets('下载校验失败显示原因与重试', (tester) async {
    await ctx.makeAvailable();
    ctx.downloader.error = const UpdateFailure(
      UpdateFailureKind.checksum,
      '安装包校验失败，已删除',
    );
    await pump(tester);

    await tester.tap(find.byKey(const ValueKey('update-download')));
    await tester.pumpAndSettle();

    expect(find.textContaining('校验失败'), findsOneWidget);
    expect(find.byKey(const ValueKey('update-retry')), findsOneWidget);
  });

  testWidgets('签名不一致时阻止安装并要求先导出', (tester) async {
    await ctx.makeAvailable();
    ctx.installer.preflightResult =
        const ApkPreflight(ok: false, reason: 'signature');
    await pump(tester);

    await tester.tap(find.byKey(const ValueKey('update-download')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('update-install')));
    await tester.pumpAndSettle();

    expect(find.textContaining('先导出'), findsOneWidget);
    expect(find.byKey(const ValueKey('update-release-page')), findsOneWidget);
    expect(ctx.installer.installCalls, 0);
  });

  testWidgets('未授权时先自动打开设置，等待授权而不是尝试安装', (tester) async {
    await ctx.makeAvailable();
    ctx.installer.canInstallValue = false;
    await pump(tester);

    await tester.tap(find.byKey(const ValueKey('update-download')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('update-install')));
    await tester.pumpAndSettle();

    expect(ctx.installer.openedSettings, isTrue);
    expect(
        find.byKey(const ValueKey('update-permission-open')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('update-permission-continue')),
      findsOneWidget,
    );
    expect(find.textContaining('请允许金豆安装未知应用'), findsOneWidget);
    expect(ctx.installer.installCalls, 0);
  });

  testWidgets('从授权页返回且已授权时自动继续安装', (tester) async {
    await ctx.makeAvailable();
    ctx.installer.canInstallValue = false;
    await pump(tester);

    await tester.tap(find.byKey(const ValueKey('update-download')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('update-install')));
    await tester.pumpAndSettle();

    ctx.installer.canInstallValue = true;
    await ctx.controller.onAppResumed();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(ctx.installer.installCalls, 1);
    expect(find.textContaining('正在打开系统安装器'), findsOneWidget);
  });

  testWidgets('授权页返回但未授权时给出「去设置」和重试', (tester) async {
    await ctx.makeAvailable();
    ctx.installer.canInstallValue = false;
    await pump(tester);

    await tester.tap(find.byKey(const ValueKey('update-download')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('update-install')));
    await tester.pumpAndSettle();

    await ctx.controller.onAppResumed();
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('update-permission')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('update-permission-retry')),
      findsOneWidget,
    );
    expect(ctx.installer.installCalls, 0);
  });
}
