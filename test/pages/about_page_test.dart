import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bean_count/pages/about_page.dart';
import 'package:bean_count/services/update/app_version.dart';
import 'package:bean_count/services/update/update_controller.dart';
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

  Future<void> pump(
    WidgetTester tester, {
    Future<AppVersion> Function()? loader,
    UpdateController? controller,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: buildBeanTheme(Brightness.light),
        home: AboutPage(
          controller: controller,
          versionLoader: loader ??
              () async =>
                  const AppVersion(version: '1.0.1', buildNumber: '2'),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('关于页展示真实版本，不出现硬编码的 v0.0.1', (tester) async {
    await pump(tester);

    expect(find.text('v1.0.1 (2)'), findsOneWidget);
    expect(find.text('v0.0.1'), findsNothing);
    expect(find.text('关于金豆'), findsOneWidget);
  });

  testWidgets('版本读取失败时显示「版本未知」且页面不崩溃', (tester) async {
    await pump(
      tester,
      loader: () async => throw StateError('package info unavailable'),
    );

    expect(find.text('版本未知'), findsOneWidget);
    expect(find.text('GitHub 仓库'), findsOneWidget);
  });

  testWidgets('展示仓库链接与更新隐私说明', (tester) async {
    await pump(tester);

    expect(find.text('GitHub 仓库'), findsOneWidget);
    expect(find.text('mayapony/beancount'), findsOneWidget);
    expect(
      find.textContaining('不上传账本数据、设备标识或账号信息'),
      findsOneWidget,
    );
  });

  testWidgets('自动检查开关默认开启，关闭后落库', (tester) async {
    await pump(tester, controller: ctx.controller);

    final toggle = find.byKey(const ValueKey('about-auto-check'));
    await tester.ensureVisible(toggle);
    expect(find.text('自动检查更新'), findsOneWidget);

    await tester.tap(toggle);
    await tester.pumpAndSettle();

    expect(await ctx.preferences.autoCheckEnabled(), isFalse);
  });

  testWidgets('手动检查已是最新时给出反馈', (tester) async {
    ctx.source.outcome = CheckOutcome(release: testRelease(version: '1.0.1'));
    await pump(tester, controller: ctx.controller);

    final tile = find.byKey(const ValueKey('about-check-update'));
    await tester.ensureVisible(tile);
    await tester.tap(tile);
    await tester.pumpAndSettle();

    expect(find.text('已是最新版本'), findsWidgets);
  });

  testWidgets('手动检查发现新版本时打开提示', (tester) async {
    ctx.source.outcome = CheckOutcome(release: testRelease());
    await pump(tester, controller: ctx.controller);

    final tile = find.byKey(const ValueKey('about-check-update'));
    await tester.ensureVisible(tile);
    await tester.tap(tile);
    await tester.pumpAndSettle();

    expect(find.text('发现新版本'), findsOneWidget);
    expect(find.text('v1.0.2'), findsOneWidget);
  });

  testWidgets('关掉提示后再检查仍提示新版本，不会卡在检查中', (tester) async {
    ctx.source.outcome = CheckOutcome(release: testRelease());
    await pump(tester, controller: ctx.controller);

    final tile = find.byKey(const ValueKey('about-check-update'));
    await tester.ensureVisible(tile);
    await tester.tap(tile);
    await tester.pumpAndSettle();
    expect(find.text('发现新版本'), findsOneWidget);

    // 点弹窗外的空白处关掉提示，并没有真的更新。
    await tester.tapAt(const Offset(1, 1));
    await tester.pumpAndSettle();
    expect(find.text('发现新版本'), findsNothing);

    // 再次检查时服务端返回 304：仍然应该提示同一新版本。
    ctx.source.outcome = const CheckOutcome.notModified(etag: 'W/"e"');
    await tester.ensureVisible(tile);
    await tester.tap(tile);
    await tester.pumpAndSettle();

    expect(find.text('发现新版本'), findsOneWidget);
    expect(find.text('正在检查…'), findsNothing);
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });

  testWidgets('手动检查失败时显示原因', (tester) async {
    ctx.source.error = const UpdateFailure(
      UpdateFailureKind.timeout,
      '检查更新超时，稍后再试',
    );
    await pump(tester, controller: ctx.controller);

    final tile = find.byKey(const ValueKey('about-check-update'));
    await tester.ensureVisible(tile);
    await tester.tap(tile);
    await tester.pumpAndSettle();

    expect(find.textContaining('检查更新超时'), findsWidgets);
  });
}
