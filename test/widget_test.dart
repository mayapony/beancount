import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bean_count/main.dart';
import 'package:bean_count/utils/money.dart';

void main() {
  test('金额使用千分位分隔', () {
    expect(formatMoney(1234567.89), '1,234,567.89');
    expect(formatMoney(8.5), '8.50');
    expect(formatMoneyCompact(12800), '12,800');
  });

  testWidgets('首页渲染四 Tab 与中心金豆', (tester) async {
    await tester.pumpWidget(const BeanApp());
    await tester.pump(const Duration(milliseconds: 400));

    // 四个导航标签：明细 / 洞察 / 资产 / 设置
    expect(find.text('明细'), findsOneWidget);
    expect(find.text('洞察'), findsWidgets);
    expect(find.text('资产'), findsWidgets);
    expect(find.text('设置'), findsOneWidget);

    // 首页不再显示品牌标题，保持干净
    expect(find.text('金豆'), findsNothing);

    // 中心停靠的金豆 FAB
    expect(find.byIcon(Icons.add_rounded), findsOneWidget);
  });
}
