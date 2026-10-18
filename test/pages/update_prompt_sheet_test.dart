import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bean_count/theme/app_theme.dart';
import 'package:bean_count/widgets/update_prompt_sheet.dart';

import '../support/update_fakes.dart';

void main() {
  late UpdateTestContext ctx;

  setUp(() async {
    ctx = await UpdateTestContext.create();
    await ctx.makeAvailable();
  });

  tearDown(() async {
    await ctx.close();
  });

  Future<void> openSheet(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: buildBeanTheme(Brightness.light),
        home: Scaffold(
          body: Builder(
            builder: (context) => Center(
              child: ElevatedButton(
                onPressed: () => showUpdatePrompt(context, ctx.controller),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  testWidgets('提示展示版本、体积、说明与三个动作', (tester) async {
    await openSheet(tester);

    expect(find.text('发现新版本'), findsOneWidget);
    expect(find.text('v1.0.2'), findsOneWidget);
    expect(find.textContaining('47.9 MB'), findsOneWidget);
    expect(find.textContaining('应用内检查更新'), findsOneWidget);
    expect(find.byKey(const ValueKey('update-now')), findsOneWidget);
    expect(find.byKey(const ValueKey('update-later')), findsOneWidget);
    expect(find.byKey(const ValueKey('update-skip')), findsOneWidget);
  });

  testWidgets('以后再说会记录 dismissed 并关闭提示', (tester) async {
    await openSheet(tester);

    await tester.tap(find.byKey(const ValueKey('update-later')));
    await tester.pumpAndSettle();

    expect(find.text('发现新版本'), findsNothing);
    final dismissed = await ctx.preferences.dismissed();
    expect(dismissed?.version, '1.0.2');
    expect(ctx.controller.phase.name, 'idle');
  });

  testWidgets('跳过此版本会记录 skipped 并关闭提示', (tester) async {
    await openSheet(tester);

    await tester.tap(find.byKey(const ValueKey('update-skip')));
    await tester.pumpAndSettle();

    expect(find.text('发现新版本'), findsNothing);
    expect(await ctx.preferences.skippedVersion(), '1.0.2');
  });

  testWidgets('立即更新进入更新页', (tester) async {
    await openSheet(tester);

    await tester.tap(find.byKey(const ValueKey('update-now')));
    await tester.pumpAndSettle();

    expect(find.text('更新到 v1.0.2'), findsOneWidget);
    expect(find.byKey(const ValueKey('update-install')), findsOneWidget);
  });
}
