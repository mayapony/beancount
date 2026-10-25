import 'package:bean_count/data/db/app_database.dart';
import 'package:bean_count/data/db/connection.dart';
import 'package:bean_count/data/repositories/app_state_repository.dart';
import 'package:bean_count/services/capture/capture_candidate.dart';
import 'package:bean_count/services/capture/capture_rule.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late AppDatabase db;
  late CaptureRuleStore store;

  setUp(() async {
    db = AppDatabase(openInMemoryConnection());
    store = CaptureRuleStore(AppStateRepository(db));
    await db.select(db.appState).get(); // 建库
  });

  tearDown(() async => db.close());

  CaptureRule rule({
    String id = 'r1',
    String pkg = 'com.tencent.mm',
    RuleTarget target = RuleTarget.accessibility,
    String? fingerprint = 'fp-abc',
    AmountStrategy strategy = AmountStrategy.regex,
    String? pattern = r'支付[¥￥]\s*(\d+(?:\.\d{1,2})?)',
  }) {
    return CaptureRule(
      id: id,
      packageName: pkg,
      target: target,
      surfaceFingerprint: fingerprint,
      direction: CaptureDirection.expense,
      amountStrategy: strategy,
      amountPattern: pattern,
      excludeKeywords: const ['余额'],
      version: 1,
      tier: CaptureRuleTier.pending,
      confirmations: 0,
    );
  }

  test('存取 round-trip', () async {
    await store.save([rule()]);

    final loaded = await store.load();
    expect(loaded, hasLength(1));
    final r = loaded.single;
    expect(r.id, 'r1');
    expect(r.packageName, 'com.tencent.mm');
    expect(r.target, RuleTarget.accessibility);
    expect(r.surfaceFingerprint, 'fp-abc');
    expect(r.direction, CaptureDirection.expense);
    expect(r.amountStrategy, AmountStrategy.regex);
    expect(r.amountPattern, r'支付[¥￥]\s*(\d+(?:\.\d{1,2})?)');
    expect(r.excludeKeywords, ['余额']);
    expect(r.tier, CaptureRuleTier.pending);
  });

  test('save 递增版本，rollback 恢复上一版', () async {
    await store.save([rule(id: 'a')]);
    final v1 = await store.currentVersion();
    expect(v1, 1);

    await store.save([rule(id: 'b')]);
    expect(await store.currentVersion(), 2);

    final restored = await store.rollback();
    expect(restored, isNotNull);
    expect(restored!.single.id, 'a');
    expect((await store.load()).single.id, 'a');
  });

  test('无 LKG 时 rollback 返回 null', () async {
    expect(await store.rollback(), isNull);
    await store.save([rule()]);
    expect(await store.rollback(), isNull); // 只存过一次，没有上一版
  });

  test('空存储 load 返回空列表', () async {
    expect(await store.load(), isEmpty);
  });

  test('多规则 round-trip 保持顺序', () async {
    await store.save([rule(id: 'a'), rule(id: 'b', target: RuleTarget.notification, fingerprint: null)]);
    final loaded = await store.load();
    expect(loaded.map((r) => r.id), ['a', 'b']);
    expect(loaded[1].target, RuleTarget.notification);
    expect(loaded[1].surfaceFingerprint, isNull);
  });
}
