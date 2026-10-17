import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../data/db/app_database.dart';
import '../data/db/enums.dart';
import '../data/repositories/account_repository.dart';
import '../services/export/bee_count_csv_writer.dart' show formatCents;
import '../services/import/bee_count_csv.dart' show parseAmountToCents;
import '../theme/tokens.dart';
import '../utils/money.dart';
import '../widgets/common.dart';

/// 账户管理：改名字、类型、期初余额，删掉建错的账户。
class AccountsPage extends StatefulWidget {
  const AccountsPage({super.key, required this.repository});

  final AccountRepository repository;

  @override
  State<AccountsPage> createState() => _AccountsPageState();
}

class _AccountsPageState extends State<AccountsPage> {
  List<AccountBalance> _items = const [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    final items = await widget.repository.withBalances();
    if (!mounted) return;
    setState(() {
      _items = items;
      _loading = false;
    });
  }

  Future<void> _openEditor({Account? account}) async {
    final changed = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _AccountEditor(
        repository: widget.repository,
        existing: account,
      ),
    );
    if (changed == true) await _reload();
  }

  @override
  Widget build(BuildContext context) {
    final palette = BeanPalette.of(context);

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        leading: IconButton(
          tooltip: '返回',
          icon: const Icon(Icons.chevron_left_rounded, size: 28),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: const Text(
          '账户',
          style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
        ),
        centerTitle: true,
        actions: [
          IconButton(
            tooltip: '新建账户',
            icon: const Icon(Icons.add_rounded, size: 24),
            onPressed: () => _openEditor(),
          ),
        ],
      ),
      body: _loading
          ? const SizedBox.shrink()
          : ListView(
              padding: const EdgeInsets.fromLTRB(
                BeanSpace.page,
                8,
                BeanSpace.page,
                40,
              ),
              children: [
                BeanCard(
                  padding: EdgeInsets.zero,
                  child: Column(
                    children: [
                      for (var i = 0; i < _items.length; i++) ...[
                        _AccountRow(
                          item: _items[i],
                          onTap: () => _openEditor(account: _items[i].account),
                        ),
                        if (i != _items.length - 1)
                          Divider(
                            height: BeanSpace.hairline,
                            thickness: BeanSpace.hairline,
                            indent: 58,
                            color: palette.border,
                          ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: BeanSpace.section),
                Text(
                  '余额 = 期初余额 + 收入 − 支出，由交易推导，不单独存。',
                  style: TextStyle(
                    fontSize: 12,
                    color: palette.textSecondary,
                  ),
                ),
              ],
            ),
    );
  }
}

String _typeLabel(AccountType type) {
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

IconData _typeIcon(AccountType type) {
  switch (type) {
    case AccountType.wallet:
      return Icons.account_balance_wallet_rounded;
    case AccountType.debit:
      return Icons.credit_card_rounded;
    case AccountType.credit:
      return Icons.credit_card_rounded;
    case AccountType.other:
      return Icons.savings_rounded;
  }
}

class _AccountRow extends StatelessWidget {
  const _AccountRow({required this.item, required this.onTap});

  final AccountBalance item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = BeanPalette.of(context);
    final balance = item.balanceCents / 100;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(
          children: [
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                color: palette.neutral.sand,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(
                _typeIcon(item.account.type),
                size: 18,
                color: palette.textSecondary,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.account.name,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    [
                  _typeLabel(item.account.type),
                  if (item.account.currency != 'CNY') item.account.currency,
                  '${item.count} 笔',
                ].join(' · '),
                    style: TextStyle(
                      fontSize: 12,
                      color: palette.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
            AmountText(
              balance,
              fontSize: 15,
              fontWeight: FontWeight.w500,
              showSign: false,
              color: balance < 0 ? palette.alert : null,
            ),
            Icon(
              Icons.chevron_right_rounded,
              size: 20,
              color: palette.textSecondary,
            ),
          ],
        ),
      ),
    );
  }
}

/// 新建 / 编辑账户面板。
class _AccountEditor extends StatefulWidget {
  const _AccountEditor({required this.repository, this.existing});

  final AccountRepository repository;
  final Account? existing;

  @override
  State<_AccountEditor> createState() => _AccountEditorState();
}

class _AccountEditorState extends State<_AccountEditor> {
  late final TextEditingController _name =
      TextEditingController(text: widget.existing?.name ?? '');
  late final TextEditingController _initial = TextEditingController(
    text: widget.existing == null
        ? ''
        : formatCents(widget.existing!.initialBalanceCents),
  );
  late AccountType _type = widget.existing?.type ?? AccountType.wallet;
  late String _currency = widget.existing?.currency ?? 'CNY';
  late final TextEditingController _billingDay = TextEditingController(
    text: widget.existing?.billingDay?.toString() ?? '',
  );
  late final TextEditingController _dueDay = TextEditingController(
    text: widget.existing?.dueDay?.toString() ?? '',
  );
  String? _error;
  bool _saving = false;

  bool get _isNew => widget.existing == null;

  @override
  void dispose() {
    _name.dispose();
    _initial.dispose();
    _billingDay.dispose();
    _dueDay.dispose();
    super.dispose();
  }

  /// 空 → 0（不设置）；非法 → -1；合法 → 1..28。
  int _parseDay(String raw) {
    final text = raw.trim();
    if (text.isEmpty) return 0;
    final value = int.tryParse(text);
    if (value == null || value < 1 || value > 28) return -1;
    return value;
  }

  int? _parseInitial() {
    final text = _initial.text.trim();
    if (text.isEmpty) return 0;
    return parseAmountToCents(text);
  }

  Future<void> _save() async {
    final name = _name.text.trim();
    if (name.isEmpty) {
      setState(() => _error = '账户名不能为空');
      return;
    }
    final initial = _parseInitial();
    if (initial == null) {
      setState(() => _error = '期初余额要写成数字，如 1234.50');
      return;
    }
    final billingDay = _parseDay(_billingDay.text);
    final dueDay = _parseDay(_dueDay.text);
    if (billingDay == -1 || dueDay == -1) {
      setState(() => _error = '账单日/还款日只能是 1–28');
      return;
    }

    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      if (_isNew) {
        await widget.repository.create(
          name: name,
          type: _type,
          initialBalanceCents: initial,
          currency: _currency,
          billingDay: _type == AccountType.credit && billingDay > 0
              ? billingDay
              : null,
          dueDay:
              _type == AccountType.credit && dueDay > 0 ? dueDay : null,
        );
      } else {
        final isCredit = _type == AccountType.credit;
        await widget.repository.update(
          widget.existing!.id,
          name: name,
          type: _type,
          initialBalanceCents: initial,
          currency: _currency,
          billingDay: isCredit && billingDay > 0 ? billingDay : null,
          clearBillingDay: !isCredit || billingDay == 0,
          dueDay: isCredit && dueDay > 0 ? dueDay : null,
          clearDueDay: !isCredit || dueDay == 0,
        );
      }
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } on DuplicateAccountNameException catch (error) {
      setState(() {
        _saving = false;
        _error = '$error';
      });
    } catch (error) {
      setState(() {
        _saving = false;
        _error = '$error';
      });
    }
  }

  Future<void> _delete() async {
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.repository.delete(widget.existing!.id);
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } on AccountInUseException catch (error) {
      setState(() {
        _saving = false;
        _error = '$error';
      });
    } catch (error) {
      setState(() {
        _saving = false;
        _error = '$error';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = BeanPalette.of(context);

    return BeanSheet(
      title: _isNew ? '新建账户' : '编辑账户',
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _name,
              autofocus: _isNew,
              decoration: const InputDecoration(
                labelText: '名称',
                isDense: true,
              ),
            ),
            const SizedBox(height: 14),
            Text(
              '类型',
              style: TextStyle(fontSize: 13, color: palette.textSecondary),
            ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 8,
              children: [
                for (final type in AccountType.values)
                  GestureDetector(
                    onTap: () => setState(() => _type = type),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 7,
                      ),
                      decoration: BoxDecoration(
                        color: _type == type
                            ? palette.goldDeep
                            : palette.neutral.sand,
                        borderRadius: BorderRadius.circular(9),
                      ),
                      child: Text(
                        _typeLabel(type),
                        style: TextStyle(
                          fontSize: 13,
                          color: _type == type
                              ? Theme.of(context).colorScheme.onPrimary
                              : palette.textSecondary,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _initial,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[0-9.\-]')),
              ],
              decoration: const InputDecoration(
                labelText: '期初余额',
                hintText: '0.00',
                isDense: true,
              ),
            ),
            const SizedBox(height: 14),
            Text(
              '币种',
              style: TextStyle(fontSize: 13, color: palette.textSecondary),
            ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 8,
              children: [
                for (final code in const ['CNY', 'USD', 'EUR', 'JPY', 'HKD'])
                  GestureDetector(
                    onTap: () => setState(() => _currency = code),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 7,
                      ),
                      decoration: BoxDecoration(
                        color: _currency == code
                            ? palette.goldDeep
                            : palette.neutral.sand,
                        borderRadius: BorderRadius.circular(9),
                      ),
                      child: Text(
                        code,
                        style: TextStyle(
                          fontSize: 13,
                          color: _currency == code
                              ? Theme.of(context).colorScheme.onPrimary
                              : palette.textSecondary,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            if (_type == AccountType.credit) ...[
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _billingDay,
                      keyboardType: TextInputType.number,
                      inputFormatters: [
                        FilteringTextInputFormatter.digitsOnly,
                        LengthLimitingTextInputFormatter(2),
                      ],
                      decoration: const InputDecoration(
                        labelText: '账单日（1–28）',
                        hintText: '留空表示不提醒',
                        isDense: true,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextField(
                      controller: _dueDay,
                      keyboardType: TextInputType.number,
                      inputFormatters: [
                        FilteringTextInputFormatter.digitsOnly,
                        LengthLimitingTextInputFormatter(2),
                      ],
                      decoration: const InputDecoration(
                        labelText: '还款日（1–28）',
                        hintText: '资产页会提醒',
                        isDense: true,
                      ),
                    ),
                  ),
                ],
              ),
            ],
            if (_error != null) ...[
              const SizedBox(height: 10),
              Text(
                _error!,
                style: TextStyle(fontSize: 12, color: palette.alert),
              ),
            ],
            const SizedBox(height: 16),
            Row(
              children: [
                if (!_isNew)
                  TextButton(
                    onPressed: _saving ? null : _delete,
                    style: TextButton.styleFrom(foregroundColor: palette.alert),
                    child: const Text('删除账户'),
                  ),
                const Spacer(),
                TextButton(
                  onPressed: _saving ? null : () => Navigator.of(context).pop(),
                  child: const Text('取消'),
                ),
                const SizedBox(width: 4),
                FilledButton(
                  onPressed: _saving ? null : _save,
                  child: Text(_saving ? '保存中…' : '保存'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
