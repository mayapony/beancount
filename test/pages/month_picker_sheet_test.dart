import 'package:bean_count/theme/app_theme.dart';
import 'package:bean_count/utils/month.dart';
import 'package:bean_count/widgets/month_picker_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  /// 起一个带按钮的页面，点按钮弹出月份面板；返回读取选中结果的闭包。
  Future<LedgerMonth? Function()> pumpPicker(
    WidgetTester tester, {
    required LedgerMonth current,
  }) async {
    LedgerMonth? picked;
    await tester.pumpWidget(
      MaterialApp(
        theme: buildBeanTheme(Brightness.light),
        home: Scaffold(
          body: Center(
            child: Builder(
              builder: (context) => TextButton(
                onPressed: () async {
                  picked = await MonthPickerSheet.show(context, current: current);
                },
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    return () => picked;
  }

  testWidgets('选月份后返回该月，并高亮当前浏览月', (tester) async {
    final picked = await pumpPicker(tester, current: const LedgerMonth(2026, 10));

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.text('选择月份'), findsOneWidget);
    expect(find.text('2026年'), findsOneWidget);

    await tester.tap(find.text('3月'));
    await tester.pumpAndSettle();

    expect(picked(), const LedgerMonth(2026, 3));
  });

  testWidgets('年份可前后步进', (tester) async {
    final picked = await pumpPicker(tester, current: const LedgerMonth(2026, 10));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('上一年'));
    await tester.pumpAndSettle();
    expect(find.text('2025年'), findsOneWidget);

    await tester.tap(find.text('12月'));
    await tester.pumpAndSettle();
    expect(picked(), const LedgerMonth(2025, 12));
  });

  testWidgets('「回到本月」返回当前自然月', (tester) async {
    final picked = await pumpPicker(tester, current: const LedgerMonth(2020, 5));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('回到本月'));
    await tester.pumpAndSettle();

    expect(picked(), LedgerMonth.current());
  });
}
