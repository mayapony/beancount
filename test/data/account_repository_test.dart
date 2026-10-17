import 'package:bean_count/data/db/app_database.dart';
import 'package:drift/drift.dart' show Value;
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
    await db.select(db.accounts).get(); // 建库 + 种子
  });

  tearDown(() async => db.close());

  test('余额 = 初始余额 + 收入 − 支出', () async {
    final account = await accounts.ensure(name: '钱包');
    await (db.update(db.accounts)..where((t) => t.id.equals(account.id))).write(
      const AccountsCompanion(initialBalanceCents: Value(100000)),
    );

    final food = (await categories.findByName('餐饮', CategoryType.expense))!;
    final salary = (await categories.findByName('工资', CategoryType.income))!;

    await transactions.create(
      NewTransaction(
        type: EntryType.expense,
        amountCents: 3850,
        categoryId: food.id,
        accountId: account.id,
        happenedAt: DateTime(2026, 10, 17, 12),
        note: '午餐',
      ),
    );
    await transactions.create(
      NewTransaction(
        type: EntryType.income,
        amountCents: 200000,
        categoryId: salary.id,
        accountId: account.id,
        happenedAt: DateTime(2026, 10, 15, 10),
        note: '工资',
      ),
    );

    final result = (await accounts.withBalances())
        .firstWhere((a) => a.account.id == account.id);

    // 1000.00 − 38.50 + 2000.00
    expect(result.balanceCents, 100000 - 3850 + 200000);
    expect(result.count, 2);
  });

  test('种子账户初始余额为 0、还没有交易时余额也是 0', () async {
    final result = (await accounts.withBalances()).single;
    expect(result.account.name, '默认账户');
    expect(result.balanceCents, 0);
    expect(result.count, 0);
  });

  test('导入用的 ensure 按名字复用，初始余额一律 0', () async {
    final first = await accounts.ensure(name: '支付宝');
    final second = await accounts.ensure(name: '支付宝');

    expect(second.id, first.id);
    expect(first.initialBalanceCents, 0);
    expect(await accounts.all(), hasLength(2), reason: '默认账户 + 支付宝');
  });

  test('没有交易的账户也出现在列表里', () async {
    await accounts.ensure(name: '微信');
    final list = await accounts.withBalances();
    expect(list.map((a) => a.account.name), containsAll(['默认账户', '微信']));
  });

  test('create 建账户：id 不与名称绑定，重名被拒', () async {
    final created = await accounts.create(
      name: '招商银行卡',
      type: AccountType.debit,
      initialBalanceCents: 2856000,
    );
    expect(created.id, isNot(contains('招商')));
    expect(created.initialBalanceCents, 2856000);
    expect(created.type, AccountType.debit);

    await expectLater(
      accounts.create(name: '招商银行卡'),
      throwsA(isA<DuplicateAccountNameException>()),
    );
  });

  test('update 改名/改类型/改期初余额，余额随之变化', () async {
    final account = await accounts.ensure(name: '钱包');
    final food = (await categories.findByName('餐饮', CategoryType.expense))!;
    await transactions.create(
      NewTransaction(
        type: EntryType.expense,
        amountCents: 3850,
        categoryId: food.id,
        accountId: account.id,
        happenedAt: DateTime(2026, 10, 17, 12),
        note: '牛肉面',
      ),
    );

    await accounts.update(
      account.id,
      name: '日常钱包',
      type: AccountType.credit,
      initialBalanceCents: 200000,
    );

    final updated = (await accounts.withBalances())
        .firstWhere((a) => a.account.id == account.id);
    expect(updated.account.name, '日常钱包');
    expect(updated.account.type, AccountType.credit);
    expect(updated.balanceCents, 200000 - 3850);
    expect(updated.count, 1);

    // 改成别人已用的名字会被拒
    await accounts.create(name: '支付宝');
    await expectLater(
      accounts.update(account.id, name: '支付宝'),
      throwsA(isA<DuplicateAccountNameException>()),
    );
  });

  test('delete：有交易引用被拒，无引用可删', () async {
    final used = await accounts.ensure(name: '有账账户');
    final empty = await accounts.ensure(name: '空账户');
    final food = (await categories.findByName('餐饮', CategoryType.expense))!;
    await transactions.create(
      NewTransaction(
        type: EntryType.expense,
        amountCents: 1000,
        categoryId: food.id,
        accountId: used.id,
        happenedAt: DateTime(2026, 10, 17, 9),
        note: '一笔',
      ),
    );

    expect(await accounts.usageCount(used.id), 1);
    await expectLater(
      accounts.delete(used.id),
      throwsA(isA<AccountInUseException>()),
    );
    expect(await accounts.byId(used.id), isNotNull);

    await accounts.delete(empty.id);
    expect(await accounts.byId(empty.id), isNull);
  });
}
