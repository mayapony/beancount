import 'package:flutter/material.dart';

import '../data/db/app_database.dart';
import '../data/db/enums.dart';
import '../data/repositories/account_repository.dart';
import '../data/repositories/category_repository.dart';
import '../data/repositories/recurring_repository.dart';
import '../services/export/bee_count_csv_writer.dart' show formatCents;
import '../services/import/bee_count_csv.dart' show parseAmountToCents;
import '../services/recurring/recurring_schedule.dart';
import '../theme/tokens.dart';
import '../utils/money.dart';
import '../widgets/common.dart';

/// 循环记账：规则列表 + 新建/编辑。
class RecurringPage extends StatefulWidget {
  const RecurringPage({
    super.key,
    required this.rules,
    required this.categories,
    required this.accounts,
  });

  final RecurringRepository rules;
  final CategoryRepository categories;
  final AccountRepository accounts;

  @override
  State<RecurringPage> createState() => _RecurringPageState();
}

class _RecurringPageState extends State<RecurringPage> {
  List<RecurringRule> _rules = const [];
  List<Category> _categories = const [];
  List<AccountBalance> _accounts = const [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    final rules = await widget.rules.all();
    final categories = await widget.categories.allCategories();
    final accounts = await widget.accounts.withBalances();
    if (!mounted) return;
    setState(() {
      _rules = rules;
      _categories = categories;
      _accounts = accounts;
      _loading = false;
    });
  }

  Future<void> _openEditor({RecurringRule? rule}) async {
    final changed = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _RuleEditor(
        repository: widget.rules,
        categories: [
          for (final c in _categories)
            if (c.parentId == null) c,
        ],
        accounts: _accounts,
        existing: rule,
      ),
    );
    if (changed == true) await _reload();
  }

  String _titleOf(RecurringRule rule) {
    if (rule.note.trim().isNotEmpty) return rule.note.trim();
    if (rule.type == EntryType.transfer) {
      final from = _accounts
          .where((a) => a.account.id == rule.accountId)
          .map((a) => a.account.name)
          .firstOrNull;
      final to = _accounts
          .where((a) => a.account.id == rule.toAccountId)
          .map((a) => a.account.name)
          .firstOrNull;
      return '${from ?? '账户'} → ${to ?? '账户'}';
    }
    return _categories
            .where((c) => c.id == rule.categoryId)
            .map((c) => c.name)
            .firstOrNull ??
        '未命名';
  }

  @override
  Widget build(BuildContext context) {
    final palette = BeanPalette.of(context);
    final now = DateTime.now();

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
          '循环记账',
          style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
        ),
        centerTitle: true,
        actions: [
          IconButton(
            tooltip: '新建规则',
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
                if (_rules.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 40),
                    child: Text(
                      '还没有循环规则。房租、工资、会员这类固定收支可以在这里配一次，之后每次打开 App 自动补记。',
                      style: TextStyle(
                        fontSize: 13,
                        color: palette.textSecondary,
                      ),
                    ),
                  )
                else
                  BeanCard(
                    padding: EdgeInsets.zero,
                    child: Column(
                      children: [
                        for (var i = 0; i < _rules.length; i++) ...[
                          _RuleRow(
                            title: _titleOf(_rules[i]),
                            rule: _rules[i],
                            next: nextDueDate(_rules[i], now),
                            onTap: () => _openEditor(rule: _rules[i]),
                          ),
                          if (i != _rules.length - 1)
                            Divider(
                              height: BeanSpace.hairline,
                              thickness: BeanSpace.hairline,
                              indent: 16,
                              color: palette.border,
                            ),
                        ],
                      ],
                    ),
                  ),
                const SizedBox(height: BeanSpace.section),
                Text(
                  '补记发生在打开 App 时：同一条规则的同一期只会补一次，改过金额也不会重复补。',
                  style: TextStyle(fontSize: 12, color: palette.textSecondary),
                ),
              ],
            ),
    );
  }
}

class _RuleRow extends StatelessWidget {
  const _RuleRow({
    required this.title,
    required this.rule,
    required this.next,
    required this.onTap,
  });

  final String title;
  final RecurringRule rule;
  final DateTime next;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = BeanPalette.of(context);
    final amount = rule.type == EntryType.income
        ? '+${formatMoney(rule.amountCents / 100)}'
        : formatMoney(rule.amountCents / 100);

    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                      if (!rule.enabled) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: palette.neutral.sand,
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            '已暂停',
                            style: TextStyle(
                              fontSize: 11,
                              color: palette.textSecondary,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${frequencyLabel(rule)} · ${amount == '' ? '' : '¥'}'
                    '$amount',
                    style: TextStyle(
                      fontSize: 12,
                      color: palette.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
            Text(
              rule.enabled ? '下次 ${next.month}月${next.day}日' : '已暂停',
              style: TextStyle(fontSize: 12, color: palette.textSecondary),
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

/// 新建 / 编辑规则的面板。
class _RuleEditor extends StatefulWidget {
  const _RuleEditor({
    required this.repository,
    required this.categories,
    required this.accounts,
    this.existing,
  });

  final RecurringRepository repository;
  final List<Category> categories;
  final List<AccountBalance> accounts;
  final RecurringRule? existing;

  @override
  State<_RuleEditor> createState() => _RuleEditorState();
}

class _RuleEditorState extends State<_RuleEditor> {
  late EntryType _type = widget.existing?.type ?? EntryType.expense;
  late final TextEditingController _amount = TextEditingController(
    text: widget.existing == null
        ? ''
        : formatCents(widget.existing!.amountCents),
  );
  late final TextEditingController _note =
      TextEditingController(text: widget.existing?.note ?? '');
  late String? _categoryId = widget.existing?.categoryId;
  late String? _accountId = widget.existing?.accountId;
  late String? _toAccountId = widget.existing?.toAccountId;
  late int _day = widget.existing?.dayOfMonth ?? 1;
  late bool _enabled = widget.existing?.enabled ?? true;
  String? _error;
  bool _saving = false;

  bool get _isNew => widget.existing == null;

  @override
  void dispose() {
    _amount.dispose();
    _note.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final cents = parseAmountToCents(_amount.text.trim());
    if (cents == null || cents <= 0) {
      setState(() => _error = '金额要写成数字，如 2500.00');
      return;
    }
    final categoryId = _type == EntryType.transfer
        ? null
        : (_categoryId ??
            widget.categories
                .where((c) => c.type.name == _type.name)
                .map((c) => c.id)
                .firstOrNull);
    final accountId = _accountId ??
        (widget.accounts.isEmpty ? null : widget.accounts.first.account.id);
    final toAccountId = _toAccountId ??
        (widget.accounts.length < 2
            ? null
            : widget.accounts[1].account.id);

    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      if (_isNew) {
        final now = DateTime.now();
        await widget.repository.create(
          type: _type,
          amountCents: cents,
          categoryId: categoryId,
          accountId: accountId,
          toAccountId: _type == EntryType.transfer ? toAccountId : null,
          note: _note.text,
          dayOfMonth: _day,
          startYear: now.year,
          startMonth: now.month,
        );
      } else {
        await widget.repository.update(
          widget.existing!.id,
          type: _type,
          amountCents: cents,
          categoryId: categoryId,
          clearCategory: categoryId == null,
          accountId: accountId,
          clearAccount: accountId == null,
          toAccountId: _type == EntryType.transfer ? toAccountId : null,
          clearToAccount: _type != EntryType.transfer,
          note: _note.text,
          dayOfMonth: _day,
          enabled: _enabled,
        );
      }
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (error) {
      setState(() {
        _saving = false;
        _error = '$error';
      });
    }
  }

  Future<void> _delete() async {
    setState(() => _saving = true);
    await widget.repository.delete(widget.existing!.id);
    if (!mounted) return;
    Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final palette = BeanPalette.of(context);
    final categories = [
      for (final c in widget.categories)
        if (c.type.name == (_type == EntryType.income ? 'income' : 'expense'))
          c,
    ];

    return BeanSheet(
      title: _isNew ? '新建循环规则' : '编辑循环规则',
      child: SizedBox(
        height: 470,
        child: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        for (final type in EntryType.values)
                          Padding(
                            padding: const EdgeInsets.only(right: 8),
                            child: _Chip(
                              label: switch (type) {
                                EntryType.expense => '支出',
                                EntryType.income => '收入',
                                EntryType.transfer => '转账',
                              },
                              selected: _type == type,
                              onTap: () => setState(() {
                                _type = type;
                                _categoryId = null;
                              }),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _amount,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      decoration: const InputDecoration(
                        labelText: '金额',
                        hintText: '0.00',
                        isDense: true,
                      ),
                    ),
                    if (_type != EntryType.transfer) ...[
                      _label('分类', palette),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          for (final category in categories)
                            _Chip(
                              label: category.name,
                              selected: _categoryId == category.id,
                              onTap: () =>
                                  setState(() => _categoryId = category.id),
                            ),
                        ],
                      ),
                    ] else ...[
                      _label('从 / 到', palette),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          for (final account in widget.accounts)
                            _Chip(
                              label: '从 ${account.account.name}',
                              selected: _accountId == account.account.id,
                              onTap: () =>
                                  setState(() => _accountId = account.account.id),
                            ),
                          for (final account in widget.accounts)
                            _Chip(
                              label: '到 ${account.account.name}',
                              selected: _toAccountId == account.account.id,
                              onTap: () => setState(
                                () => _toAccountId = account.account.id,
                              ),
                            ),
                        ],
                      ),
                    ],
                    _label('每月几号', palette),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (var day = 1; day <= 28; day++)
                          _Chip(
                            label: '$day',
                            selected: _day == day,
                            onTap: () => setState(() => _day = day),
                          ),
                        _Chip(
                          label: '月末',
                          selected: _day >= 29,
                          onTap: () => setState(() => _day = 31),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _note,
                      maxLength: 40,
                      decoration: const InputDecoration(
                        labelText: '备注',
                        hintText: '例如：房租',
                        isDense: true,
                        counterText: '',
                      ),
                    ),
                    if (_error != null) ...[
                      const SizedBox(height: 8),
                      Text(
                        _error!,
                        style: TextStyle(fontSize: 12, color: palette.alert),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 4),
              child: Row(
                children: [
                  if (!_isNew)
                    TextButton(
                      onPressed: _saving ? null : _delete,
                      style: TextButton.styleFrom(
                        foregroundColor: palette.alert,
                      ),
                      child: const Text('删除'),
                    ),
                  if (!_isNew)
                    GestureDetector(
                      onTap: () => setState(() => _enabled = !_enabled),
                      child: Padding(
                        padding: const EdgeInsets.only(left: 4),
                        child: Text(
                          _enabled ? '已启用' : '已暂停',
                          style: TextStyle(
                            fontSize: 13,
                            color: palette.textSecondary,
                          ),
                        ),
                      ),
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
            ),
          ],
        ),
      ),
    );
  }

  Widget _label(String text, BeanPalette palette) => Padding(
        padding: const EdgeInsets.only(top: 12, bottom: 8),
        child: Text(
          text,
          style: TextStyle(fontSize: 13, color: palette.textSecondary),
        ),
      );
}

class _Chip extends StatelessWidget {
  const _Chip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = BeanPalette.of(context);
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: selected ? palette.goldDeep : palette.neutral.sand,
          borderRadius: BorderRadius.circular(9),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 13,
            color: selected
                ? Theme.of(context).colorScheme.onPrimary
                : palette.textSecondary,
          ),
        ),
      ),
    );
  }
}
