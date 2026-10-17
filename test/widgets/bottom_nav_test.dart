import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bean_count/main.dart';

void main() {
  testWidgets('底部导航四个 Tab 的索引映射正确', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.625;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(const BeanApp());
    await tester.pump(const Duration(milliseconds: 400));

    int currentIndex() =>
        tester.widget<IndexedStack>(find.byType(IndexedStack)).index!;

    expect(currentIndex(), 0, reason: '默认应在明细');

    await tester.tap(find.byIcon(Icons.donut_small_rounded));
    await tester.pump(const Duration(milliseconds: 300));
    expect(currentIndex(), 1, reason: '点洞察应到索引 1');

    await tester.tap(find.byIcon(Icons.account_balance_wallet_rounded));
    await tester.pump(const Duration(milliseconds: 300));
    expect(currentIndex(), 2, reason: '点资产应到索引 2');

    await tester.tap(find.byIcon(Icons.settings_rounded));
    await tester.pump(const Duration(milliseconds: 300));
    expect(currentIndex(), 3, reason: '点设置应到索引 3');

    await tester.tap(find.byIcon(Icons.receipt_long_rounded));
    await tester.pump(const Duration(milliseconds: 300));
    expect(currentIndex(), 0, reason: '点明细应回到索引 0');
  });
}
