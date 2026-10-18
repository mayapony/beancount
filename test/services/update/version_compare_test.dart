import 'package:flutter_test/flutter_test.dart';

import 'package:bean_count/services/update/version_compare.dart';

void main() {
  group('parseVersion', () {
    test('解析 v 前缀、build 与 prerelease 后缀', () {
      expect(parseVersion('v1.2.3'), [1, 2, 3]);
      expect(parseVersion('1.2.3+4'), [1, 2, 3]);
      expect(parseVersion('1.2.3-beta.1'), [1, 2, 3]);
      expect(parseVersion(' V2.0 '), [2, 0]);
    });

    test('非法输入返回 null', () {
      expect(parseVersion(''), isNull);
      expect(parseVersion('v'), isNull);
      expect(parseVersion('1.x.3'), isNull);
      expect(parseVersion('1..3'), isNull);
      expect(parseVersion('1.2.'), isNull);
      expect(parseVersion('-1.2'), isNull);
    });
  });

  group('compareVersions', () {
    test('按数字段比较，而不是按字符串', () {
      expect(compareVersions('1.0.10', '1.0.9'), greaterThan(0));
      expect(compareVersions('1.0.9', '1.0.10'), lessThan(0));
      expect(compareVersions('2.0', '1.99.99'), greaterThan(0));
    });

    test('缺省段按 0 处理', () {
      expect(compareVersions('1.0', '1.0.0'), 0);
      expect(compareVersions('1', '1.0.0'), 0);
    });

    test('忽略 v 前缀与后缀', () {
      expect(compareVersions('v1.2.3', '1.2.3'), 0);
      expect(compareVersions('1.2.3+9', '1.2.3'), 0);
      expect(compareVersions('1.2.3-beta', '1.2.3'), 0);
    });

    test('非法输入按不可比较处理', () {
      expect(compareVersions('1.0.0', 'bad'), 0);
      expect(compareVersions('bad', '1.0.0'), 0);
      expect(compareVersions('bad', 'worse'), 0);
    });
  });

  group('isNewerVersion', () {
    test('只有严格更大才算新版本', () {
      expect(isNewerVersion('1.0.2', '1.0.1'), isTrue);
      expect(isNewerVersion('1.0.1', '1.0.1'), isFalse);
      expect(isNewerVersion('1.0.0', '1.0.1'), isFalse);
      expect(isNewerVersion('bad', '1.0.1'), isFalse);
    });
  });
}
