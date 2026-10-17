import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bean_count/theme/app_theme.dart';
import 'package:bean_count/widgets/quick_entry_sheet.dart';

void main() {
  testWidgets('金额面板可渲染、能输入、能写备注、能换账户', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.75;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    QuickEntryDraft? submitted;

    await tester.pumpWidget(
      MaterialApp(
        theme: buildBeanTheme(Brightness.light),
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () => showModalBottomSheet<void>(
                  context: context,
                  isScrollControlled: true,
                  builder: (_) => QuickEntrySheet(
                    onSubmit: (draft) => submitted = draft,
                  ),
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    // 结构：类型分段、4×3 分类、金额占位、备注行、键盘
    expect(find.text('支出'), findsOneWidget);
    expect(find.text('记一笔'), findsOneWidget);
    expect(find.text('点击填写备注'), findsOneWidget);
    expect(find.text('完成'), findsOneWidget);
    expect(find.text('7'), findsOneWidget);

    // 账户：默认取第一个 demo 账户，点开可换
    expect(find.text('日常钱包'), findsOneWidget);
    await tester.tap(find.text('日常钱包'));
    await tester.pumpAndSettle();
    expect(find.text('选择账户'), findsOneWidget);
    await tester.tap(find.text('招商银行卡'));
    await tester.pumpAndSettle();
    expect(find.text('招商银行卡'), findsOneWidget);

    // 金额 38.5
    for (final key in ['3', '8', '.', '5']) {
      await tester.tap(find.text(key).last);
      await tester.pump();
    }

    // 备注：弹窗输入后回填到备注行
    await tester.tap(find.text('点击填写备注'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField), '和家人吃晚饭');
    await tester.tap(find.text('确定'));
    await tester.pumpAndSettle();
    expect(find.textContaining('和家人吃晚饭'), findsOneWidget);

    // 时间：默认今天；点开能换成「昨天」
    expect(find.textContaining('今天'), findsOneWidget);
    await tester.tap(find.textContaining('今天'));
    await tester.pumpAndSettle();
    expect(find.text('记账时间'), findsOneWidget);
    await tester.tap(find.text('昨天'));
    await tester.pump();
    await tester.tap(find.text('完成').last);
    await tester.pumpAndSettle();
    expect(find.textContaining('昨天'), findsOneWidget);

    // 提交
    await tester.tap(find.text('完成').last);
    await tester.pumpAndSettle();
    expect(submitted?.amount, 38.5);
    expect(submitted?.note, '和家人吃晚饭');
    expect(submitted?.account, '招商银行卡');
    expect(
      submitted!.time
          .isBefore(DateTime.now().subtract(const Duration(hours: 1))),
      isTrue,
    );
  });
}
