import 'package:flutter/material.dart';

import '../data/db/enums.dart';
import '../data/repositories/account_repository.dart';
import '../theme/tokens.dart';
import '../utils/money.dart';
import '../widgets/common.dart';

/// 资产页：净资产即标题，下面按账户列出余额。
///
/// 余额**全部由交易推导**（初始余额 + 收入 − 支出），不存冗余字段，
/// 所以删账、改账都不会让数字漂移。
class AssetsPage extends StatefulWidget {
  const AssetsPage({super.key, required this.repository});

  final AccountRepository repository;

  @override
  State<AssetsPage> createState() => _AssetsPageState();
}

class _AssetsPageState extends State<AssetsPage> {
  late final Stream<List<AccountBalance>> _stream =
      widget.repository.watchWithBalances();

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<AccountBalance>>(
      stream: _stream,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return const SafeArea(
            bottom: false,
            child: BeanEmptyState(
              title: '数据暂时打不开',
              subtitle: '本地数据库没准备好，重启 App 再试',
            ),
          );
        }
        final accounts = snapshot.data;
        if (accounts == null) return const SizedBox.shrink();
        if (accounts.isEmpty) {
          return const SafeArea(
            bottom: false,
            child: BeanEmptyState(
              title: '还没有账户',
              subtitle: '记一笔时会自动使用默认账户',
            ),
          );
        }
        return _AssetsBody(accounts: accounts);
      },
    );
  }
}

class _AssetsBody extends StatelessWidget {
  const _AssetsBody({required this.accounts});

  final List<AccountBalance> accounts;

  @override
  Widget build(BuildContext context) {
    final palette = BeanPalette.of(context);

    final totalAssets = accounts
        .where((a) => a.balanceCents > 0)
        .fold<int>(0, (sum, a) => sum + a.balanceCents);
    final totalDebts = accounts
        .where((a) => a.balanceCents < 0)
        .fold<int>(0, (sum, a) => sum + a.balanceCents.abs());
    final netWorth = totalAssets - totalDebts;

    return SafeArea(
      bottom: false,
      child: ListView(
        padding: const EdgeInsets.only(bottom: 120),
        children: [
          // 标题就是净资产本身：一个数字承担定位 + 层级 + 锚点
          BeanLargeTitle(
            title: _signed(netWorth),
            subtitle: '净资产 · 共 ${accounts.length} 个账户',
          ),

          // ── 资产构成 ──────────────────────────────────────
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: BeanSpace.page),
            child: BeanCard(
              child: Row(
                children: [
                  Expanded(
                    child: _SubMetric(
                      label: '总资产',
                      child: _Money(
                        cents: totalAssets,
                        color: palette.income,
                      ),
                    ),
                  ),
                  Container(
                    width: BeanSpace.hairline,
                    height: 30,
                    color: palette.border,
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: _SubMetric(
                      label: '总负债',
                      child: _Money(
                        cents: -totalDebts,
                        color: totalDebts > 0 ? palette.alert : null,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: BeanSpace.section),

          // ── 账户列表 ─────────────────────────────────────
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: BeanSpace.page),
            child: BeanCard(
              padding: EdgeInsets.zero,
              child: Column(
                children: [
                  for (var i = 0; i < accounts.length; i++) ...[
                    _AccountRow(item: accounts[i]),
                    if (i != accounts.length - 1)
                      Divider(
                        height: BeanSpace.hairline,
                        thickness: BeanSpace.hairline,
                        indent: 62,
                        color: palette.border,
                      ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 负号放在 ¥ 前面：`-¥38.50` 读作"欠了 38.50"。
String _signed(int cents) =>
    '${cents < 0 ? '-' : ''}¥${formatMoney(cents.abs() / 100)}';

class _SubMetric extends StatelessWidget {
  const _SubMetric({required this.label, required this.child});

  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final palette = BeanPalette.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(fontSize: 11, color: palette.textSecondary),
        ),
        const SizedBox(height: 4),
        child,
      ],
    );
  }
}

class _AccountRow extends StatelessWidget {
  const _AccountRow({required this.item});

  final AccountBalance item;

  @override
  Widget build(BuildContext context) {
    final palette = BeanPalette.of(context);
    final account = item.account;
    final count = item.count;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
      child: Row(
        children: [
          _AccountAvatar(type: account.type),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  account.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 17,
                    height: 1.25,
                    letterSpacing: -0.2,
                    fontWeight: FontWeight.w400,
                  ),
                ),
                const SizedBox(height: 1),
                Text(
                  count == 0
                      ? '${_typeLabel(account.type)} · 还没有记账'
                      : '${_typeLabel(account.type)} · $count 笔',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13,
                    height: 1.2,
                    color: palette.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          // 余额用「符号 + ¥ + 两位小数」：欠款是 -¥3,280.40
          _Money(
            cents: item.balanceCents,
            color: item.balanceCents < 0 ? palette.alert : null,
          ),
        ],
      ),
    );
  }

  static String _typeLabel(AccountType type) {
    switch (type) {
      case AccountType.wallet:
        return '钱包';
      case AccountType.debit:
        return '储蓄卡';
      case AccountType.credit:
        return '信用卡';
      case AccountType.other:
        return '其他';
    }
  }
}

/// 账户头像：实心圆 + 白色字形，颜色按账户类型固定，方便扫视。
class _AccountAvatar extends StatelessWidget {
  const _AccountAvatar({required this.type});

  final AccountType type;

  @override
  Widget build(BuildContext context) {
    final (color, icon) = switch (type) {
      AccountType.wallet => (BeanColors.gold, Icons.account_balance_wallet_rounded),
      AccountType.debit => (const Color(0xFF3B82F6), Icons.credit_card_rounded),
      AccountType.credit => (const Color(0xFF8B5CF6), Icons.credit_score_rounded),
      AccountType.other => (const Color(0xFF64748B), Icons.savings_rounded),
    };
    return Container(
      width: 30,
      height: 30,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      child: Icon(icon, size: 16, color: Colors.white),
    );
  }
}

/// 带货币符号的金额：`-¥3,280.40` / `¥1,240.55`。
class _Money extends StatelessWidget {
  const _Money({required this.cents, this.color});

  final int cents;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final negative = cents < 0;
    return Text(
      '${negative ? '-' : ''}¥${formatMoney(cents.abs() / 100)}',
      style: TextStyle(
        fontSize: 17,
        letterSpacing: -0.2,
        fontWeight: FontWeight.w500,
        color: color,
        fontFeatures: const [FontFeature.tabularFigures()],
      ),
    );
  }
}
