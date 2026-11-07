import 'package:bean_count/data/db/app_database.dart';
import 'package:bean_count/data/db/connection.dart';
import 'package:bean_count/data/repositories/app_state_repository.dart';
import 'package:bean_count/services/capture/capture_diagnostics.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('CaptureDiagEvent', () {
    test('JSON 往返保持字段', () {
      final event = CaptureDiagEvent(
        seq: 1730000000000000,
        at: DateTime(2026, 11, 7, 18, 30),
        kind: CaptureDiagKind.noRule,
        packageName: 'com.tencent.mm',
        target: 'accessibility',
        ok: false,
        reason: 'no_rule',
        detail: const {
          'fingerprint': 'a1b2c3d4',
          'rules': <Object?>[],
        },
        evidenceId: 'ev-1',
        count: 3,
      );

      final restored = CaptureDiagEvent.fromJson(event.toJson())!;

      expect(restored.seq, event.seq);
      expect(restored.at, event.at);
      expect(restored.kind, CaptureDiagKind.noRule);
      expect(restored.packageName, 'com.tencent.mm');
      expect(restored.target, 'accessibility');
      expect(restored.ok, isFalse);
      expect(restored.reason, 'no_rule');
      expect(restored.detail['fingerprint'], 'a1b2c3d4');
      expect(restored.evidenceId, 'ev-1');
      expect(restored.count, 3);
    });

    test('缺省字段不写进 JSON 也能读回', () {
      final restored = CaptureDiagEvent.fromJson({
        'seq': 1,
        'at': '2026-11-07T10:00:00.000Z',
        'kind': 'entry_written',
      })!;

      expect(restored.kind, CaptureDiagKind.entryWritten);
      expect(restored.ok, isTrue);
      expect(restored.count, 1);
      expect(restored.detail, isEmpty);
      expect(restored.packageName, isNull);
    });

    test('不认识的类别返回 null 而不是抛异常', () {
      expect(
        CaptureDiagEvent.fromJson({
          'seq': 1,
          'at': '2026-11-07T10:00:00.000Z',
          'kind': 'future_kind_from_newer_version',
        }),
        isNull,
      );
    });

    test('时间非法返回 null', () {
      expect(
        CaptureDiagEvent.fromJson({'seq': 1, 'at': 'not-a-date', 'kind': 'no_rule'}),
        isNull,
      );
    });

    test('非 Map 输入返回 null', () {
      expect(CaptureDiagEvent.fromJson('nope'), isNull);
      expect(CaptureDiagEvent.fromJson(null), isNull);
    });
  });

  group('CaptureDiagKind', () {
    test('wire 字符串稳定且唯一', () {
      final wires = CaptureDiagKind.values.map((k) => k.wire).toList();
      expect(wires.toSet().length, wires.length);
      expect(CaptureDiagKind.noRule.wire, 'no_rule');
    });

    test('按 wire 还原', () {
      for (final kind in CaptureDiagKind.values) {
        expect(CaptureDiagKind.fromWire(kind.wire), kind);
      }
      expect(CaptureDiagKind.fromWire('unknown'), isNull);
      expect(CaptureDiagKind.fromWire(null), isNull);
    });
  });

  group('CaptureDiagStore', storeTests);
  group('CaptureDiagEvidenceStore', evidenceTests);
}

void storeTests() {
  late AppDatabase db;
  late CaptureDiagStore store;

  setUp(() async {
    db = AppDatabase(openInMemoryConnection());
    store = CaptureDiagStore(AppStateRepository(db));
    await db.select(db.appState).get(); // 建库
  });

  tearDown(() async => db.close());

  final base = DateTime(2026, 11, 7, 10);
  CaptureDiagEvent eventAt(int minute, {CaptureDiagKind? kind}) => CaptureDiagEvent(
        seq: base.add(Duration(minutes: minute)).microsecondsSinceEpoch,
        at: base.add(Duration(minutes: minute)),
        kind: kind ?? CaptureDiagKind.treeCaptured,
        packageName: 'com.tencent.mm',
      );

  test('按时间升序读出', () async {
    await store.record(eventAt(3));
    await store.record(eventAt(1));
    await store.record(eventAt(2));

    final events = await store.readAll();
    expect(events.map((e) => e.at.minute), [1, 2, 3]);
  });

  test('超过上限淘汰最旧的', () async {
    for (var i = 0; i < 250; i++) {
      await store.record(eventAt(i));
    }

    final events = await store.readAll();
    expect(events, hasLength(200));
    expect(events.first.at, base.add(const Duration(minutes: 50)));
    expect(events.last.at, base.add(const Duration(minutes: 249)));
  });

  test('clear 清空全部记录', () async {
    await store.record(eventAt(1));
    await store.record(eventAt(2));

    await store.clear();

    expect(await store.readAll(), isEmpty);
  });

  test('坏数据行不影响其余记录', () async {
    final state = AppStateRepository(db);
    await state.write('diag_event:${'0' * 19}', 'not json');
    await store.record(eventAt(1));

    final events = await store.readAll();
    expect(events, hasLength(1));
    expect(events.single.kind, CaptureDiagKind.treeCaptured);
  });
}

void evidenceTests() {
  late AppDatabase db;
  late CaptureDiagEvidenceStore store;

  setUp(() async {
    db = AppDatabase(openInMemoryConnection());
    store = CaptureDiagEvidenceStore(AppStateRepository(db));
    await db.select(db.appState).get();
  });

  tearDown(() async => db.close());

  test('存进去能原样读回', () async {
    final id = await store.save('PageNode|微信支付\n  ¥12.00', at: DateTime(2026, 11, 7, 10));
    expect(await store.read(id), contains('微信支付'));
  });

  test('超过上限淘汰最旧的证据', () async {
    final ids = <String>[];
    for (var i = 0; i < 12; i++) {
      ids.add(await store.save('dump-$i', at: DateTime(2026, 11, 7, 10, i)));
    }

    expect(await store.read(ids[0]), isNull);
    expect(await store.read(ids[1]), isNull);
    expect(await store.read(ids[2]), 'dump-2');
    expect(await store.read(ids[11]), 'dump-11');
  });

  test('被淘汰证据不影响引用它的事件', () async {
    final diag = CaptureDiagStore(AppStateRepository(db));
    final evidence = CaptureDiagEvidenceStore(AppStateRepository(db), maxEvidence: 1);
    final stale = await evidence.save('old', at: DateTime(2026, 11, 7, 10));
    await evidence.save('new', at: DateTime(2026, 11, 7, 10, 1));

    await diag.record(CaptureDiagEvent(
      seq: 1,
      at: DateTime(2026, 11, 7, 10, 2),
      kind: CaptureDiagKind.treeCaptured,
      evidenceId: stale,
    ));

    final events = await diag.readAll();
    expect(events.single.evidenceId, stale);
    expect(await evidence.read(stale), isNull);
  });

  test('clear 清空证据', () async {
    await store.save('dump', at: DateTime(2026, 11, 7, 10));
    await store.clear();
    expect(await store.read('ev-${DateTime(2026, 11, 7, 10).toUtc().microsecondsSinceEpoch}'), isNull);
  });
}
