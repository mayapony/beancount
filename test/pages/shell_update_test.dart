import 'package:flutter_test/flutter_test.dart';

import 'package:bean_count/main.dart';
import 'package:bean_count/services/update/app_version.dart';
import 'package:bean_count/services/update/update_models.dart';

import '../support/update_fakes.dart';

void main() {
  late UpdateTestContext ctx;

  tearDown(() async {
    await ctx.close();
  });

  Future<void> pumpApp(WidgetTester tester) async {
    await tester.pumpWidget(
      BeanApp(database: ctx.db, updateController: ctx.controller),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('启动后自动检查并弹出新版本提示', (tester) async {
    ctx = await UpdateTestContext.create();
    ctx.source.outcome = CheckOutcome(release: testRelease());

    await pumpApp(tester);

    expect(find.text('发现新版本'), findsOneWidget);
    expect(find.text('v1.0.2'), findsOneWidget);
  });

  testWidgets('跳过的版本不在启动时弹提示', (tester) async {
    ctx = await UpdateTestContext.create();
    await ctx.preferences.skipVersion('1.0.2');
    ctx.source.outcome = CheckOutcome(release: testRelease());

    await pumpApp(tester);

    expect(find.text('发现新版本'), findsNothing);
  });

  testWidgets('启动读到 pending 时提示已更新', (tester) async {
    ctx = await UpdateTestContext.create(
      current: const AppVersion(version: '1.0.2', buildNumber: '200'),
      pendingVersion: '1.0.2',
    );

    await pumpApp(tester);

    expect(find.text('已更新到 v1.0.2'), findsOneWidget);
  });
}
