import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bean_count/pages/about_page.dart';
import 'package:bean_count/services/update/app_version.dart';
import 'package:bean_count/theme/app_theme.dart';

void main() {
  Future<void> pump(
    WidgetTester tester, {
    Future<AppVersion> Function()? loader,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: buildBeanTheme(Brightness.light),
        home: AboutPage(
          versionLoader:
              loader ?? () async => const AppVersion(version: '1.0.1', buildNumber: '2'),
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
}
