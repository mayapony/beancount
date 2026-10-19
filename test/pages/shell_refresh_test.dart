import 'dart:io';

import 'package:bean_count/data/db/app_database.dart';
import 'package:bean_count/data/db/enums.dart';
import 'package:bean_count/data/repositories/account_repository.dart';
import 'package:bean_count/data/repositories/category_repository.dart';
import 'package:bean_count/data/repositories/transaction_repository.dart';
import 'package:bean_count/main.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// 回归：截屏自动记账跑在 headless engine（另一个 isolate + 另一个
/// AppDatabase 实例），写库不会触发 UI 侧 drift 流的通知。以前回到前台
/// 界面仍是旧数据，要重启才看得到。
void main() {
  late Directory tmp;
  late AppDatabase uiDb;
  late AppDatabase backgroundDb;

  setUp(() {
    // 必须在 testWidgets 的 fake async 之外创建：真实文件 I/O 在假时钟里不收敛
    tmp = Directory.systemTemp.createTempSync('bean_shell_refresh');
    final file = File('${tmp.path}/shared.sqlite');
    uiDb = AppDatabase(NativeDatabase(file));
    backgroundDb = AppDatabase(NativeDatabase(file));
  });

  tearDown(() async {
    await uiDb.close();
    await backgroundDb.close();
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
  });

  testWidgets('后台写了库、回到前台后明细页自己重查', (tester) async {
    await tester.pumpWidget(BeanApp(database: uiDb));
    await tester.pump();
    await tester.pump();
    await tester.pump();
    expect(find.text('还没有记账'), findsOneWidget);

    await _addExpenseFromBackground(backgroundDb, note: '后台记的一笔');

    await tester.pump();
    await tester.pump();
    expect(
      find.text('后台记的一笔'),
      findsNothing,
      reason: '另一条连接写库不会通知 UI 的 drift 流',
    );

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    await tester.pump();

    expect(find.text('后台记的一笔'), findsOneWidget);
  });
}

/// 模拟 headless engine：用自己那条连接写一笔当天的支出。
Future<void> _addExpenseFromBackground(
  AppDatabase db, {
  required String note,
}) async {
  final wallet = (await AccountRepository(db).all()).first;
  final food =
      (await CategoryRepository(db).findByName('餐饮', CategoryType.expense))!;
  await TransactionRepository(db).create(
    NewTransaction(
      type: EntryType.expense,
      amountCents: 1234,
      categoryId: food.id,
      accountId: wallet.id,
      happenedAt: DateTime.now(),
      note: note,
    ),
  );
}
