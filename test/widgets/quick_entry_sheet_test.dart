import 'package:bean_count/data/db/app_database.dart';
import 'package:bean_count/data/db/enums.dart';
import 'package:bean_count/data/repositories/account_repository.dart';
import 'package:bean_count/theme/app_theme.dart';
import 'package:bean_count/services/attachments/image_picker_service.dart';
import 'package:bean_count/widgets/quick_entry_sheet.dart';
import 'package:flutter/material.dart';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

Category _cat(String id, String name, CategoryType type, int order, String icon) {
  return Category(
    id: id,
    name: name,
    type: type,
    parentId: null,
    color: 0xFFF59E0B,
    icon: icon,
    sortOrder: order,
    createdAt: DateTime(2026, 1, 1),
  );
}

List<Category> _categories() => [
      _cat('cat-food', '餐饮', CategoryType.expense, 0, 'restaurant'),
      _cat('cat-transport', '交通', CategoryType.expense, 1, 'directions_bus'),
      _cat('cat-shopping', '购物', CategoryType.expense, 2, 'shopping_bag'),
      _cat('cat-entertainment', '娱乐', CategoryType.expense, 3, 'movie'),
      _cat('cat-salary', '工资', CategoryType.income, 0, 'payments'),
      _cat('cat-bonus', '奖金', CategoryType.income, 1, 'redeem'),
    ];

List<AccountBalance> _accounts() => [
      AccountBalance(
        account: Account(
          id: 'acc-wallet',
          name: '日常钱包',
          type: AccountType.wallet,
          initialBalanceCents: 124055,
          sortOrder: 0,
          currency: 'CNY',
          createdAt: DateTime(2026, 1, 1),
        ),
        expenseCents: 0,
        incomeCents: 0,
      ),
      AccountBalance(
        account: Account(
          id: 'acc-cmb',
          name: '招商银行卡',
          type: AccountType.debit,
          initialBalanceCents: 2856000,
          sortOrder: 1,
          currency: 'CNY',
          createdAt: DateTime(2026, 1, 1),
        ),
        expenseCents: 0,
        incomeCents: 0,
      ),
    ];

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
                    categories: _categories(),
                    accounts: _accounts(),
                    onSubmit: (draft) async {
                      submitted = draft;
                      return null;
                    },
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

    // 结构：类型分段、分类网格（按类型过滤）、金额占位、备注行、键盘
    expect(find.text('支出'), findsOneWidget);
    expect(find.text('记一笔'), findsOneWidget);
    expect(find.text('点击填写备注'), findsOneWidget);
    expect(find.text('完成'), findsOneWidget);
    expect(find.text('7'), findsOneWidget);

    // 支出页的分类来自数据库记录，收入分类不该出现
    expect(find.text('餐饮'), findsOneWidget);
    expect(find.text('工资'), findsNothing);

    // 切到收入：网格换成收入分类
    await tester.tap(find.text('收入'));
    await tester.pumpAndSettle();
    expect(find.text('工资'), findsOneWidget);
    expect(find.text('餐饮'), findsNothing);
    await tester.tap(find.text('支出'));
    await tester.pumpAndSettle();

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
    expect(submitted?.account?.name, '招商银行卡');
    expect(submitted?.account?.id, 'acc-cmb');
    expect(submitted?.category?.id, 'cat-food');
    expect(submitted?.isIncome, isFalse);
    expect(
      submitted!.time
          .isBefore(DateTime.now().subtract(const Duration(hours: 1))),
      isTrue,
    );
  });

  testWidgets('保存失败时面板不关闭、输入不丢，并显示原因', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.75;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

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
                    categories: _categories(),
                    accounts: _accounts(),
                    // 模拟落库失败：返回错误文案
                    onSubmit: (_) async => '保存失败，请重试',
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

    for (final key in ['3', '8']) {
      await tester.tap(find.text(key).last);
      await tester.pump();
    }
    await tester.tap(find.text('完成'));
    await tester.pumpAndSettle();

    // 面板仍在、金额仍在、错误提示已显示
    expect(find.text('记一笔'), findsOneWidget);
    expect(find.text('保存失败，请重试'), findsOneWidget);
    expect(find.text('38.00'), findsOneWidget);

    // 继续输入会清掉错误
    await tester.tap(find.text('5').last);
    await tester.pump();
    expect(find.text('保存失败，请重试'), findsNothing);
  });

  testWidgets('编辑模式：以现值预填金额/分类/账户/时间/备注/标签', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.75;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final categories = _categories();
    final accounts = _accounts();
    final draft = QuickEntryDraft(
      amount: 38.5,
      isIncome: false,
      category: categories[1], // 交通
      account: accounts[1].account, // 招商银行卡
      time: DateTime(2026, 10, 17, 12, 30),
      note: '地铁月卡',
      tags: const ['出差', '报销'],
    );

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
                    categories: categories,
                    accounts: accounts,
                    initialDraft: draft,
                    onSubmit: (d) async {
                      submitted = d;
                      return null;
                    },
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

    expect(find.text('编辑一笔'), findsOneWidget);
    expect(find.text('记一笔'), findsNothing);
    expect(find.text('38.5'), findsOneWidget);
    expect(find.textContaining('地铁月卡'), findsOneWidget);
    expect(find.text('招商银行卡'), findsOneWidget);
    expect(find.textContaining('12:30'), findsWidgets);
    expect(find.textContaining('#出差'), findsWidgets);
    expect(find.textContaining('#报销'), findsWidgets);

    await tester.tap(find.text('完成').last);
    await tester.pumpAndSettle();

    expect(submitted?.amount, 38.5);
    expect(submitted?.category?.id, 'cat-transport');
    expect(submitted?.account?.id, 'acc-cmb');
    expect(submitted?.note, '地铁月卡');
    expect(submitted?.tags, containsAll(<String>['出差', '报销']));
    expect(submitted?.time, DateTime(2026, 10, 17, 12, 30));
  });

  testWidgets('新增模式不受 initialDraft 影响：标题仍是「记一笔」、金额从 0 起', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.75;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

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
                    categories: _categories(),
                    accounts: _accounts(),
                    onSubmit: (_) async => null,
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

    expect(find.text('记一笔'), findsOneWidget);
    expect(find.text('编辑一笔'), findsNothing);
    expect(find.text('0.00'), findsOneWidget);
    expect(find.text('日常钱包'), findsOneWidget);
  });

  testWidgets('转账模式：分类网格消失，出现「从 / 到」两个账户', (tester) async {
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
                    categories: _categories(),
                    accounts: _accounts(),
                    onSubmit: (draft) async {
                      submitted = draft;
                      return null;
                    },
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

    await tester.tap(find.text('转账'));
    await tester.pumpAndSettle();

    expect(find.text('从'), findsOneWidget);
    expect(find.text('到'), findsOneWidget);
    expect(find.text('餐饮'), findsNothing, reason: '转账没有分类');

    for (final key in ['5', '0', '0']) {
      await tester.tap(find.text(key).last);
      await tester.pump();
    }
    await tester.tap(find.text('完成'));
    await tester.pumpAndSettle();

    expect(submitted, isNotNull);
    expect(submitted!.isTransfer, isTrue);
    expect(submitted!.category, isNull);
    expect(submitted!.account, isNotNull);
    expect(submitted!.toAccount, isNotNull);
    expect(
      submitted!.account!.id,
      isNot(submitted!.toAccount!.id),
      reason: '两端不能是同一个账户',
    );
    expect(submitted!.amount, 500);
  });
  testWidgets('备注弹窗显示「最近用过」，点选后填入', (tester) async {
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
                    categories: _categories(),
                    accounts: _accounts(),
                    recentNotes: const ['房租', '牛肉面'],
                    onSubmit: (draft) async {
                      submitted = draft;
                      return null;
                    },
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

    await tester.tap(find.text('点击填写备注'));
    await tester.pumpAndSettle();

    expect(find.text('最近用过'), findsOneWidget);
    await tester.tap(find.text('房租'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('确定'));
    await tester.pumpAndSettle();

    expect(find.textContaining('房租'), findsWidgets);

    for (final key in ['5', '0']) {
      await tester.tap(find.text(key).last);
      await tester.pump();
    }
    await tester.tap(find.text('完成'));
    await tester.pumpAndSettle();
    expect(submitted?.note, '房租');
  });

  testWidgets('没有历史备注时不显示「最近用过」', (tester) async {
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
                    categories: _categories(),
                    accounts: _accounts(),
                    onSubmit: (_) async => null,
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
    await tester.tap(find.text('点击填写备注'));
    await tester.pumpAndSettle();

    expect(find.text('最近用过'), findsNothing);
  });
  testWidgets('选图后草稿带一张图，点缩略图可移除', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.75;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    QuickEntryDraft? submitted;
    var picks = 0;
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
                    categories: _categories(),
                    accounts: _accounts(),
                    pickImage: (source) async {
                      picks++;
                      return PickedImage(
                        bytes: Uint8List.fromList(<int>[1, 2, 3]),
                        fileName: 'picked.png',
                      );
                    },
                    onSubmit: (draft) async {
                      submitted = draft;
                      return null;
                    },
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

    await tester.tap(find.byTooltip('从相册添加'));
    await tester.pumpAndSettle();
    expect(picks, 1);
    expect(find.text('1'), findsWidgets, reason: '按钮角标显示数量');

    for (final key in ['5', '0']) {
      await tester.tap(find.text(key).last);
      await tester.pump();
    }
    await tester.tap(find.text('完成'));
    await tester.pumpAndSettle();
    expect(submitted?.images, hasLength(1));
    expect(submitted?.images.single.fileName, 'picked.png');
  });

  testWidgets('取消选图不产生图片；移除后草稿为空', (tester) async {
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
                    categories: _categories(),
                    accounts: _accounts(),
                    pickImage: (source) async => null,
                    onSubmit: (draft) async {
                      submitted = draft;
                      return null;
                    },
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

    await tester.tap(find.byTooltip('从相册添加'));
    await tester.pumpAndSettle();
    expect(find.text('点缩略图移除'), findsNothing);

    for (final key in ['7', '0']) {
      await tester.tap(find.text(key).last);
      await tester.pump();
    }
    await tester.tap(find.text('完成'));
    await tester.pumpAndSettle();
    expect(submitted?.images, isEmpty);
  });

  testWidgets('网页版禁用选图入口', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.75;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

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
                    categories: _categories(),
                    accounts: _accounts(),
                    pickImage: null,
                    pickEnabled: false,
                    onSubmit: (_) async => null,
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

    expect(find.byTooltip('网页版暂不支持图片附件'), findsWidgets);
    expect(find.textContaining('已识别'), findsNothing);
  });
}