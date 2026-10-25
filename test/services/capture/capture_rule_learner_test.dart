import 'package:bean_count/data/db/app_database.dart';
import 'package:bean_count/data/db/connection.dart';
import 'package:bean_count/data/repositories/app_state_repository.dart';
import 'package:bean_count/services/capture/capture_candidate.dart';
import 'package:bean_count/services/capture/capture_evidence.dart';
import 'package:bean_count/services/capture/capture_rule.dart';
import 'package:bean_count/services/capture/capture_rule_generator.dart';
import 'package:bean_count/services/capture/capture_rule_learner.dart';
import 'package:bean_count/services/capture/capture_surface.dart';
import 'package:bean_count/services/capture/capture_tree.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeGenerator implements CaptureRuleGenerator {
  _FakeGenerator();

  String pattern = r'¥(\d+(?:\.\d{1,2})?)';
  int calls = 0;

  @override
  Future<CaptureRule> generate(CaptureRuleGenerationRequest request) async {
    calls++;
    return CaptureRule(
      id: 'rule-$calls',
      packageName: request.packageName,
      target: request.target,
      surfaceFingerprint: request.surfaceFingerprint,
      direction: request.direction,
      amountStrategy: AmountStrategy.regex,
      amountPattern: pattern,
      tier: CaptureRuleTier.pending,
    );
  }

  @override
  void close() {}
}

void main() {
  late AppDatabase db;
  late CaptureRuleStore rules;
  late CaptureEvidenceStore evidence;
  late CaptureSurfaceStore surfaces;

  const dump = 'android.widget.TextView|支付成功\n'
      'android.widget.TextView|¥12.50';

  setUp(() async {
    db = AppDatabase(openInMemoryConnection());
    rules = CaptureRuleStore(AppStateRepository(db));
    evidence = CaptureEvidenceStore(AppStateRepository(db));
    surfaces = CaptureSurfaceStore(AppStateRepository(db));
    await db.select(db.appState).get(); // 建库
  });

  tearDown(() async => db.close());

  Future<void> seedEvidence({int amountCents = 1250}) async {
    await evidence.add(CaptureEvidence(
      id: 'evt-1',
      packageName: 'com.tencent.mm',
      dump: dump,
      amountCents: amountCents,
      direction: CaptureDirection.expense,
      surfaceFingerprint: surfaceFingerprintOf(dumpToTree(dump)),
      createdAt: DateTime(2026, 10, 18, 12),
    ));
  }

  test('验证通过：规则升灰入库，证据被消费', () async {
    await seedEvidence();
    final generator = _FakeGenerator();

    await CaptureRuleLearner(
      db: db,
      generator: generator,
      isConfigured: () async => true,
    ).learnAll();

    expect(generator.calls, 1);
    final loaded = await rules.load();
    expect(loaded, hasLength(1));
    expect(loaded.single.tier, CaptureRuleTier.grey);
    expect(loaded.single.surfaceFingerprint, surfaceFingerprintOf(dumpToTree(dump)));
    expect(await evidence.readAll(), isEmpty);
  });

  test('验证不过：规则标待定，不自动入账', () async {
    await seedEvidence(amountCents: 999); // 真值 ≠ 规则解出的 1250
    final generator = _FakeGenerator();

    await CaptureRuleLearner(
      db: db,
      generator: generator,
      isConfigured: () async => true,
    ).learnAll();

    final loaded = await rules.load();
    expect(loaded, hasLength(1));
    expect(loaded.single.tier, CaptureRuleTier.pending);
    expect(await evidence.readAll(), isEmpty);
  });

  test('未配置云端：不生成、证据也被消费', () async {
    await seedEvidence();
    final generator = _FakeGenerator();

    await CaptureRuleLearner(
      db: db,
      generator: generator,
      isConfigured: () async => false,
    ).learnAll();

    expect(generator.calls, 0);
    expect(await rules.load(), isEmpty);
    expect(await evidence.readAll(), isEmpty);
  });

  test('已标记截图优先的 surface 不反复生成', () async {
    await seedEvidence();
    await surfaces.mark('com.tencent.mm', surfaceFingerprintOf(dumpToTree(dump)));
    final generator = _FakeGenerator();

    await CaptureRuleLearner(
      db: db,
      generator: generator,
      isConfigured: () async => true,
    ).learnAll();

    expect(generator.calls, 0);
    expect(await rules.load(), isEmpty);
  });

  test('同 surface 再生成替换旧规则', () async {
    await seedEvidence();
    await CaptureRuleLearner(
      db: db,
      generator: _FakeGenerator(),
      isConfigured: () async => true,
    ).learnAll();

    // 再来一条同 surface 留证
    await evidence.add(CaptureEvidence(
      id: 'evt-2',
      packageName: 'com.tencent.mm',
      dump: dump,
      amountCents: 1250,
      direction: CaptureDirection.expense,
      surfaceFingerprint: surfaceFingerprintOf(dumpToTree(dump)),
      createdAt: DateTime(2026, 10, 18, 13),
    ));
    await CaptureRuleLearner(
      db: db,
      generator: _FakeGenerator(),
      isConfigured: () async => true,
    ).learnAll();

    expect(await rules.load(), hasLength(1));
  });

  test('树空但有通知文本：跳过无障碍规则，生成通知规则', () async {
    await evidence.add(CaptureEvidence(
      id: 'evt-1',
      packageName: 'com.tencent.mm',
      dump: 'android.view.View', // 空树（无文字）
      amountCents: 10000,
      direction: CaptureDirection.expense,
      surfaceFingerprint: 'fp-empty',
      notificationText: '微信支付 支付 ¥100.00',
      createdAt: DateTime(2026, 10, 18, 12),
    ));
    final generator = _FakeGenerator();

    await CaptureRuleLearner(
      db: db,
      generator: generator,
      isConfigured: () async => true,
    ).learnAll();

    // 只生成一条通知规则（无障碍规则因空树被跳过）
    final loaded = await rules.load();
    expect(loaded, hasLength(1));
    expect(loaded.single.target, RuleTarget.notification);
    expect(loaded.single.tier, CaptureRuleTier.grey);
    expect(loaded.single.surfaceFingerprint, isNull);
    expect(generator.calls, 1);
  });

  test('树可读且有通知文本：生成无障碍 + 通知两条规则', () async {
    await evidence.add(CaptureEvidence(
      id: 'evt-1',
      packageName: 'com.tencent.mm',
      dump: dump,
      amountCents: 1250,
      direction: CaptureDirection.expense,
      surfaceFingerprint: surfaceFingerprintOf(dumpToTree(dump)),
      notificationText: '微信支付 支付 ¥12.50',
      createdAt: DateTime(2026, 10, 18, 12),
    ));
    final generator = _FakeGenerator();

    await CaptureRuleLearner(
      db: db,
      generator: generator,
      isConfigured: () async => true,
    ).learnAll();

    final loaded = await rules.load();
    expect(loaded, hasLength(2));
    expect(loaded.map((r) => r.target).toSet(),
        {RuleTarget.accessibility, RuleTarget.notification});
    expect(generator.calls, 2);
  });
}
