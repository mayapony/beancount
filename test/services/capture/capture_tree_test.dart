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
}

CaptureNode _chain(int n) {
  CaptureNode node = const CaptureNode();
  for (var i = 1; i < n; i++) {
    node = CaptureNode(children: [node]);
  }
  return node;
}
