import 'package:flutter_test/flutter_test.dart';

import 'package:bean_count/services/update/release_notes.dart';

const _body = '''
金豆 1.0.2

安装：下载 `app-release.apk` 直接安装。

## 变更

- feat(update): 应用内检查更新
- fix(android): 修复 release 联网
- docs: 更新发版手册
- chore(release): 版本号
- test(update): 覆盖下载校验
- perf(download): 减少一次文件读取

## 其他

- feat: 这一段不在变更段里
''';

void main() {
  test('只保留 feat/fix/perf，并按 limit 截断', () {
    final notes = parseReleaseNotes(_body, limit: 2);

    expect(notes.total, 3);
    expect(notes.items, [
      'feat(update): 应用内检查更新',
      'fix(android): 修复 release 联网',
    ]);
    expect(notes.truncated, isTrue);
  });

  test('没有 ## 变更 段时扫描全文', () {
    const body = '- feat: A\n- docs: B\n- fix: C\n';

    final notes = parseReleaseNotes(body);

    expect(notes.items, ['feat: A', 'fix: C']);
    expect(notes.total, 2);
    expect(notes.truncated, isFalse);
  });

  test('全是 docs/test/chore 时返回空列表', () {
    const body = '## 变更\n\n- docs: A\n- test: B\n- chore: C\n';

    final notes = parseReleaseNotes(body);

    expect(notes.items, isEmpty);
    expect(notes.total, 0);
    expect(notes.isEmpty, isTrue);
  });

  test('去掉 markdown 链接与反引号', () {
    const body = '## 变更\n- feat: 支持 [更新页](https://example.com) 与 `安装`\n';

    expect(parseReleaseNotes(body).items, ['feat: 支持 更新页 与 安装']);
  });

  test('空正文返回空列表', () {
    final notes = parseReleaseNotes('');

    expect(notes.items, isEmpty);
    expect(notes.isEmpty, isTrue);
  });
}
