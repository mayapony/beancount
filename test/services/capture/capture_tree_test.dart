import 'package:bean_count/services/capture/capture_tree.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  CaptureNode node({
    String? text,
    String? bounds,
    List<CaptureNode> children = const [],
  }) {
    return CaptureNode(text: text, bounds: bounds, children: children);
  }

  test('平铺文本先序拼接', () {
    final tree = node(text: '支付成功', children: [
      node(text: '¥12.50'),
      node(text: '收款方', children: [node(text: '满巍明')]),
    ]);
    expect(tree.flattenedText, '支付成功\n¥12.50\n收款方\n满巍明');
  });

  test('totalNodeCount 统计整棵树', () {
    final tree = node(children: [
      node(),
      node(children: [node()]),
    ]);
    expect(tree.totalNodeCount, 4);
  });

  test('同页指纹一致（金额不同不影响）', () {
    final a = node(text: '支付成功', bounds: '0,0,100,50', children: [
      node(text: '¥12.50', bounds: '10,60,90,80'),
    ]);
    final b = node(text: '支付成功', bounds: '0,0,100,50', children: [
      node(text: '¥88.00', bounds: '10,60,90,80'),
    ]);
    expect(surfaceFingerprintOf(a), surfaceFingerprintOf(b));
  });

  test('异页指纹不同（标签不同）', () {
    final a = node(text: '支付成功');
    final b = node(text: '收款到账');
    expect(surfaceFingerprintOf(a), isNot(surfaceFingerprintOf(b)));
  });

  test('异页指纹不同（布局不同）', () {
    final a = node(text: '支付成功', bounds: '0,0,100,50');
    final b = node(text: '支付成功', bounds: '500,500,600,550');
    expect(surfaceFingerprintOf(a), isNot(surfaceFingerprintOf(b)));
  });

  test('节点数跨桶指纹不同', () {
    expect(
      surfaceFingerprintOf(_chain(10)),
      isNot(surfaceFingerprintOf(_chain(11))),
    );
  });

  test('dumpToTree 按缩进还原层级与文本', () {
    final tree = dumpToTree([
      'android.widget.FrameLayout',
      '  android.widget.TextView|支付成功',
      '  android.widget.TextView|¥12.50',
      'android.widget.Button|完成',
    ].join('\n'));

    // 哨兵根下是两个顶层节点：FrameLayout 与 Button
    expect(tree.children, hasLength(2));
    final frame = tree.children[0];
    expect(frame.className, 'android.widget.FrameLayout');
    expect(frame.children, hasLength(2));
    expect(frame.children[0].className, 'android.widget.TextView');
    expect(frame.children[0].text, '支付成功');
    expect(frame.children[1].text, '¥12.50');
    expect(tree.children[1].className, 'android.widget.Button');
    expect(tree.children[1].text, '完成');
    expect(tree.flattenedText, '支付成功\n¥12.50\n完成');
  });

  test('dumpToTree 文本里含 | 只按首个 | 切分', () {
    final tree = dumpToTree('android.widget.TextView|支付 | 成功');
    expect(tree.children, hasLength(1));
    expect(tree.children[0].className, 'android.widget.TextView');
    expect(tree.children[0].text, '支付 | 成功');
  });

  test('dumpToTree 同一 dump 指纹一致', () {
    const dump = 'android.widget.TextView|支付成功\n'
        'android.widget.TextView|金额\n'
        'android.widget.TextView|¥12.50';
    expect(
      surfaceFingerprintOf(dumpToTree(dump)),
      surfaceFingerprintOf(dumpToTree(dump)),
    );
  });

  test('dumpToTree 空输入返回空树', () {
    expect(dumpToTree('').flattenedText, isEmpty);
  });
}

CaptureNode _chain(int n) {
  CaptureNode node = const CaptureNode();
  for (var i = 1; i < n; i++) {
    node = CaptureNode(children: [node]);
  }
  return node;
}
