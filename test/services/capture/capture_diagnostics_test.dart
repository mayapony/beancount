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
}
