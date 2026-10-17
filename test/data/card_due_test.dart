import 'package:bean_count/data/db/app_database.dart';
import 'package:bean_count/data/db/connection.dart';
import 'package:bean_count/data/db/enums.dart';
import 'package:bean_count/data/repositories/account_repository.dart';
import 'package:bean_count/data/repositories/category_repository.dart';
import 'package:bean_count/data/repositories/transaction_repository.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late AppDatabase db;
  late AccountRepository accounts;
  late TransactionRepository transactions;
  late CategoryRepository categories;

  setUp(() async {
    db = AppDatabase(openInMemoryConnection());
    accounts = AccountRepository(db);
    transactions = TransactionRepository(db);
    categories = CategoryRepository(db);
    await db.select(db.categories).get();
  });

  tearDown(() async => db.close());

  Future<Account> card({int? dueDay = 20, int? billingDay = 5, String name = '信用卡'}) =>
      accounts.create(
        name: name,
        type: AccountType.credit,
        billingDay: billingDay,
        dueDay: dueDay,
      );

  Future<void> spend(Account account, int cents, DateTime at) async {
    final food = (await categories.findByName('餐饮', CategoryType.expense))!;
    await transactions.create(
      NewTransaction(
        type: EntryType.expense,
        amountCents: cents,
        categoryId: food.id,
        accountId: account.id,
        happenedAt: at,
      ),
    );
  }

  test('账单日/还款日可保存，越界被拒', () async {
    final account = await card();
    expect(account.billingDay, 5);
    expect(account.dueDay, 20);

    await expectLater(
      accounts.create(name: '坏卡', type: AccountType.credit, dueDay: 0),
      throwsA(isA<ArgumentError>()),
    );
    await expectLater(
      accounts.update(account.id, dueDay: 31),
      throwsA(isA<ArgumentError>()),
    );
    await expectLater(
      accounts.update(account.id, billingDay: -1),
      throwsA(isA<ArgumentError>()),
    );
  });

  test('update 可以清空日期', () async {
    final account = await card();
    await accounts.update(account.id, clearDueDay: true);
    final updated = (await accounts.byId(account.id))!;
    expect(updated.dueDay, isNull);
    expect(updated.billingDay, 5, reason: '只清还款日');
  });

  test('本月未到：还有 12 天', () async {
    final account = await card(dueDay: 20);
    await spend(account, 320000, DateTime(2026, 10, 1));

    final list = await accounts.dueReminders(now: DateTime(2026, 10, 8, 9));
    final due = list.single;
    expect(due.dueDate, DateTime(2026, 10, 20));
    expect(due.owedCents, 320000);
    expect(due.daysLeft, 12);
    expect(due.isUrgent, isFalse);
  });

  test('今天正好是还款日', () async {
    final account = await card(dueDay: 20);
    await spend(account, 100000, DateTime(2026, 10, 1));

    final due = (await accounts.dueReminders(now: DateTime(2026, 10, 20, 8)))
        .single;
    expect(due.isToday, isTrue);
    expect(due.daysLeft, 0);
    expect(due.isUrgent, isTrue);
  });

  test('本月已过：跨到下个月', () async {
    final account = await card(dueDay: 20);
    await spend(account, 50000, DateTime(2026, 10, 1));

    final due = (await accounts.dueReminders(now: DateTime(2026, 10, 25)))
        .single;
    expect(due.dueDate, DateTime(2026, 11, 20));
    expect(due.daysLeft, 26);
  });

  test('跨年：12 月已过 → 次年 1 月', () async {
    final account = await card(dueDay: 10);
    await spend(account, 1000, DateTime(2026, 12, 1));

    final due = (await accounts.dueReminders(now: DateTime(2026, 12, 25)))
        .single;
    expect(due.dueDate, DateTime(2027, 1, 10));
  });

  test('已还清或正余额不提醒', () async {
    final account = await card();
    // 没有支出：余额 0
    expect(await accounts.dueReminders(now: DateTime(2026, 10, 8)), isEmpty);

    // 正余额（多还了）
    await accounts.update(account.id, initialBalanceCents: 50000);
    expect(await accounts.dueReminders(now: DateTime(2026, 10, 8)), isEmpty);
  });

  test('没设还款日、非信用卡都不提醒', () async {
    final noDay = await card(dueDay: null);
    await spend(noDay, 10000, DateTime(2026, 10, 1));
    expect(await accounts.dueReminders(now: DateTime(2026, 10, 8)), isEmpty);

    final wallet = await accounts.create(name: '钱包');
    await spend(wallet, 10000, DateTime(2026, 10, 1));
    await accounts.update(wallet.id, dueDay: 15);
    expect(
      await accounts.dueReminders(now: DateTime(2026, 10, 8)),
      isEmpty,
      reason: '只有信用卡才提醒',
    );
  });

  test('多张卡按剩余天数升序，同天按金额降序', () async {
    final soon = await card(name: '急卡', dueDay: 11);
    final later = await card(name: '慢卡', dueDay: 23);
    final sameDayBig = await card(name: '大额卡', dueDay: 11);

    await spend(soon, 10000, DateTime(2026, 10, 1));
    await spend(later, 20000, DateTime(2026, 10, 1));
    await spend(sameDayBig, 90000, DateTime(2026, 10, 1));

    final list = await accounts.dueReminders(now: DateTime(2026, 10, 8));
    expect(list.map((d) => d.account.name).toList(), ['大额卡', '急卡', '慢卡']);
    expect(list.map((d) => d.daysLeft).toList(), [3, 3, 15]);
  });
}
