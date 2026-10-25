import 'package:bean_count/data/db/app_database.dart';
import 'package:bean_count/data/db/connection.dart';
import 'package:bean_count/data/db/enums.dart';
import 'package:bean_count/data/repositories/app_state_repository.dart';
import 'package:bean_count/services/capture/capture_candidate.dart';
import 'package:bean_count/services/capture/capture_rule.dart';
import 'package:bean_count/services/capture/capture_runtime.dart';
import 'package:bean_count/services/capture/capture_settings.dart';
import 'package:bean_count/services/capture/capture_tree.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeNotifier implements CaptureNotifier {
  final List<({int amountCents, String note})> entries = [];

  @override
  Future<void> notifyEntry({required int amountCents, required String note}) async {
    entries.add((amountCents: amountCents, note: note));
  }
}

void main() {
  late AppDatabase db;
  late CaptureRuleStore rules;
  late CaptureSettingsStore settings;
  late _FakeNotifier notifier;

  final now = DateTime(2026, 10, 18, 19, 27, 30);

  CaptureRuntime runtime() => CaptureRuntime(
        db: db,
        notifier: notifier,
        clock: () => now,
      );

  setUp(() async {
    db = AppDatabase(openInMemoryConnection());
    rules = CaptureRuleStore(AppStateRepository(db));
    settings = CaptureSettingsStore(AppStateRepository(db));
    notifier = _FakeNotifier();
    await db.select(db.categories).get(); // 建库 + 种子分类
    await settings.setEnabled(true);
  });

  tearDown(() async => db.close());

  CaptureRule notificationRule({
    CaptureRuleTier tier = CaptureRuleTier.active,
    String pattern = r'支付\s*[¥￥]\s*(\d+(?:\.\d{1,2})?)',
  }) {
    return CaptureRule(
      id: 'n1',
      packageName: 'com.tencent.mm',
      target: RuleTarget.notification,
      direction: CaptureDirection.expense,
      amountStrategy: AmountStrategy.regex,
      amountPattern: pattern,
      tier: tier,
      confirmations: 0,
    );
  }

  test('通知命中规则直接入账并弹通知', () async {
    await rules.save([notificationRule()]);

    final r = runtime();
    await r.onNotificationCaptured(
      packageName: 'com.tencent.mm',
      text: '支付 ¥12.00',
    );
    await r.flush();

    final rows = await db.select(db.transactions).get();
    expect(rows, hasLength(1));
    expect(rows.single.amountCents, 1200);
    expect(rows.single.type, EntryType.expense);
    expect(rows.single.source, EntrySource.auto);
    expect(rows.single.note, '支付 ¥12.00');
    expect(notifier.entries, hasLength(1));
    expect(notifier.entries.single.amountCents, 1200);
  });

  test('无障碍命中规则按指纹匹配并入账', () async {
    const dump = 'android.widget.TextView|支付成功\n'
        'android.widget.TextView|¥12.50';
    final fingerprint = surfaceFingerprintOf(dumpToTree(dump));
    await rules.save([
      CaptureRule(
        id: 'a1',
        packageName: 'com.tencent.mm',
        target: RuleTarget.accessibility,
        surfaceFingerprint: fingerprint,
        direction: CaptureDirection.expense,
        amountStrategy: AmountStrategy.regex,
        amountPattern: r'¥(\d+(?:\.\d{1,2})?)',
        tier: CaptureRuleTier.grey,
      ),
    ]);

    final r = runtime();
    await r.onTreeCaptured(packageName: 'com.tencent.mm', dump: dump);
    await r.flush();

    final rows = await db.select(db.transactions).get();
    expect(rows, hasLength(1));
    expect(rows.single.amountCents, 1250);
    expect(rows.single.source, EntrySource.auto);
  });

  test('通知与页面同金额同时到达只记一笔', () async {
    const dump = 'android.widget.TextView|支付成功\n'
        'android.widget.TextView|¥12.00';
    final fingerprint = surfaceFingerprintOf(dumpToTree(dump));
    await rules.save([
      notificationRule(),
      CaptureRule(
        id: 'a1',
        packageName: 'com.tencent.mm',
        target: RuleTarget.accessibility,
        surfaceFingerprint: fingerprint,
        direction: CaptureDirection.expense,
        amountStrategy: AmountStrategy.regex,
        amountPattern: r'¥(\d+(?:\.\d{1,2})?)',
        tier: CaptureRuleTier.active,
      ),
    ]);

    final r = runtime();
    await r.onNotificationCaptured(
      packageName: 'com.tencent.mm',
      text: '支付 ¥12.00',
    );
    await r.onTreeCaptured(packageName: 'com.tencent.mm', dump: dump);
    await r.flush();

    expect(await db.select(db.transactions).get(), hasLength(1));
    expect(notifier.entries, hasLength(1));
  });

  test('pending 规则不自动入账', () async {
    await rules.save([notificationRule(tier: CaptureRuleTier.pending)]);

    final r = runtime();
    await r.onNotificationCaptured(
      packageName: 'com.tencent.mm',
      text: '支付 ¥12.00',
    );
    await r.flush();

    expect(await db.select(db.transactions).get(), isEmpty);
    expect(notifier.entries, isEmpty);
  });

  test('无匹配规则不入账', () async {
    final r = runtime();
    await r.onNotificationCaptured(
      packageName: 'com.tencent.mm',
      text: '支付 ¥12.00',
    );
    await r.flush();

    expect(await db.select(db.transactions).get(), isEmpty);
    expect(notifier.entries, isEmpty);
  });

  test('关闭时即使有规则也不入账', () async {
    await rules.save([notificationRule()]);
    await settings.setEnabled(false);

    final r = runtime();
    await r.onNotificationCaptured(
      packageName: 'com.tencent.mm',
      text: '支付 ¥12.00',
    );
    await r.flush();

    expect(await db.select(db.transactions).get(), isEmpty);
  });

  test('命中后推进失效心跳时间', () async {
    await rules.save([notificationRule()]);

    final r = runtime();
    await r.onNotificationCaptured(
      packageName: 'com.tencent.mm',
      text: '支付 ¥12.00',
    );
    await r.flush();

    final saved = await settings.load();
    expect(saved.lastCaptureAt, isNotNull);
    expect(
      isCaptureStale(enabled: true, lastCaptureAt: saved.lastCaptureAt, now: now),
      isFalse,
    );
  });

  test('收入方向写入收入分类', () async {
    await rules.save([
      CaptureRule(
        id: 'i1',
        packageName: 'com.tencent.mm',
        target: RuleTarget.notification,
        direction: CaptureDirection.income,
        amountStrategy: AmountStrategy.regex,
        amountPattern: r'收款\s*[¥￥]\s*(\d+(?:\.\d{1,2})?)',
        tier: CaptureRuleTier.active,
      ),
    ]);

    final r = runtime();
    await r.onNotificationCaptured(
      packageName: 'com.tencent.mm',
      text: '收款 ¥50.00',
    );
    await r.flush();

    final row = (await db.select(db.transactions).get()).single;
    expect(row.type, EntryType.income);
    expect(row.amountCents, 5000);
  });
}
