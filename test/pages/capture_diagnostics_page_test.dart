import 'package:bean_count/data/db/app_database.dart';
import 'package:bean_count/data/db/connection.dart';
import 'package:bean_count/data/repositories/app_state_repository.dart';
import 'package:bean_count/pages/capture_diagnostics_page.dart';
import 'package:bean_count/services/capture/capture_channel.dart';
import 'package:bean_count/services/capture/capture_diagnostics.dart';
import 'package:bean_count/services/capture/capture_rule.dart';
import 'package:bean_count/services/capture/capture_settings.dart';
import 'package:bean_count/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// 假的原生通道：把「服务在跑 / 原生环形」这两件事握在测试手里。
class _FakePlatform extends CapturePlatform {
  _FakePlatform({this.service, this.nativeDiag});

  Map<String, Object?>? service;
  String? nativeDiag;
  bool cleared = false;
  bool accessibility = true;
  bool notification = true;
  final calls = <String>[];

  @override
  bool get isSupported => true;

  @override
  Future<bool> setEnabled(bool enabled) async => true;

  @override
  Future<bool> isAccessibilityEnabled() async => accessibility;

  @override
  Future<bool> isNotificationListenerEnabled() async => notification;

  @override
  Future<void> openAccessibilitySettings() async {}

  @override
  Future<void> openNotificationListenerSettings() async {}

  @override
  Future<bool> takeOpenAutoEntries() async => false;

  @override
  Future<String?> readNativeDiag() async => nativeDiag;

  @override
  Future<Map<String, Object?>?> nativeServiceState() async => service;

  @override
  Future<void> clearNativeDiag() async {
    cleared = true;
    nativeDiag = '[]';
  }

  @override
  void setNativeListeners({Future<void> Function()? onOpenAutoEntries}) {}
}

void main() {
  late AppDatabase db;
  late CaptureSettingsStore settings;
  late CaptureRuleStore rules;
  late CaptureDiagnostics diag;
  late _FakePlatform platform;

  setUp(() async {
    db = AppDatabase(openInMemoryConnection());
    final state = AppStateRepository(db);
    settings = CaptureSettingsStore(state);
    rules = CaptureRuleStore(state);
    diag = CaptureDiagnostics.forDatabase(db);
    platform = _FakePlatform(
      service: {'running': true, 'started_at': 0, 'stopped_at': 0},
    );
    await db.select(db.appState).get();
  });

  tearDown(() async => db.close());

  Widget harness({Future<DateTime?> Function()? lastAutoEntryAt}) => MaterialApp(
        theme: buildBeanTheme(Brightness.light),
        home: CaptureDiagnosticsPage(
          settings: settings,
          platform: platform,
          rules: rules,
          diag: diag,
          lastAutoEntryAt: lastAutoEntryAt,
        ),
      );

  testWidgets('规则为零时明确提示自动记账不会触发', (tester) async {
    await tester.pumpWidget(harness());
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('capture-diag-no-rules')), findsOneWidget);
    expect(find.textContaining('自动记账不会触发'), findsOneWidget);
    expect(find.text('从未'), findsWidgets);
  });

  testWidgets('有规则时不再提示，且显示档位分布', (tester) async {
    await rules.save([
      CaptureRule(
        id: 'r1',
        packageName: 'com.tencent.mm',
        target: RuleTarget.notification,
        amountStrategy: AmountStrategy.regex,
        amountPattern: r'支付(\d+)',
        tier: CaptureRuleTier.grey,
      ),
    ]);

    await tester.pumpWidget(harness());
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('capture-diag-no-rules')), findsNothing);
    expect(find.textContaining('灰度 1'), findsOneWidget);
  });

  testWidgets('从未入账时明确显示「从未」', (tester) async {
    await tester.pumpWidget(harness(lastAutoEntryAt: () async => null));
    await tester.pumpAndSettle();

    expect(find.text('从未'), findsWidgets);
  });

  testWidgets('事件流显示无规则事件，展开可见两侧指纹', (tester) async {
    final fingerprint = await diag.saveEvidence('dump');
    await diag.store.record(CaptureDiagEvent(
      seq: 1,
      at: DateTime(2026, 11, 7, 18, 30),
      kind: CaptureDiagKind.noRule,
      packageName: 'com.tencent.mm',
      ok: false,
      reason: 'no_rule',
      evidenceId: fingerprint,
      detail: {
        'fingerprint': 'aaaa1111',
        'rules': [
          {'tier': 'grey', 'fingerprint': 'bbbb2222'},
        ],
      },
    ));

    await tester.pumpWidget(harness());
    await tester.pumpAndSettle();

    expect(find.textContaining('没有可用规则'), findsOneWidget);

    await tester.tap(find.textContaining('没有可用规则'));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const Key('capture-diag-fingerprint-current')),
      findsOneWidget,
    );
    expect(find.text('本次指纹 aaaa1111'), findsOneWidget);
    expect(find.text('规则库指纹 grey bbbb2222'), findsOneWidget);
    expect(find.textContaining('dump'), findsOneWidget);
  });

  testWidgets('清空记录需要二次确认，确认后清掉两源', (tester) async {
    await diag.store.record(CaptureDiagEvent(
      seq: 1,
      at: DateTime(2026, 11, 7, 18, 30),
      kind: CaptureDiagKind.gateClosed,
      ok: false,
      reason: 'capture_disabled',
    ));

    await tester.pumpWidget(harness());
    await tester.pumpAndSettle();
    expect(find.textContaining('前置条件未满足'), findsOneWidget);

    await tester.tap(find.byKey(const Key('capture-diag-clear')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('capture-diag-clear-confirm')));
    await tester.pumpAndSettle();

    expect(await diag.events(), isEmpty);
    expect(platform.cleared, isTrue);
    expect(find.textContaining('前置条件未满足'), findsNothing);
    expect(find.text('还没有记录'), findsOneWidget);
  });

  testWidgets('服务未运行时状态卡明确标出', (tester) async {
    platform.service = {
      'running': false,
      'started_at': 0,
      'stopped_at': 0,
    };
    await tester.pumpWidget(harness());
    await tester.pumpAndSettle();

    expect(find.text('未运行'), findsOneWidget);
  });
}
