import 'dart:async';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

import '../data/db/app_database.dart';
import '../data/db/enums.dart';
import '../data/repositories/account_repository.dart';
import '../data/repositories/attachment_repository.dart';
import '../data/repositories/category_repository.dart';
import '../data/repositories/ledger_filter.dart';
import '../data/repositories/transaction_repository.dart';
import '../services/attachments/image_picker_service.dart';
import '../services/export/bee_count_csv_writer.dart' show formatCents;
import '../services/import/bee_count_csv.dart' show parseAmountToCents;
import '../theme/tokens.dart';
import '../widgets/common.dart';
import '../widgets/ledger_day_list.dart';
import 'transaction_detail_page.dart';

/// 搜索页：关键词 + 结构化条件，结果与明细同一套排版。
class SearchPage extends StatefulWidget {
  const SearchPage({
    super.key,
    required this.repository,
    this.attachments,
    this.categories,
    this.accounts,
  });

  final TransactionRepository repository;
  final AttachmentRepository? attachments;
  final CategoryRepository? categories;
  final AccountRepository? accounts;

  @override
  State<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends State<SearchPage> {
  final TextEditingController _keyword = TextEditingController();
  LedgerFilter _filter = const LedgerFilter();
  SearchResult? _result;
  bool _searching = false;
  Timer? _debounce;

  /// 筛选面板要的候选（进页面取一次）。
  List<Category> _categories = const [];
  List<AccountBalance> _accounts = const [];
  List<String> _tags = const [];

  @override
  void initState() {
    super.initState();
    widget.attachments?.ensureReady();
    _loadChoices();
    _run();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _keyword.dispose();
    super.dispose();
  }

  Future<void> _loadChoices() async {
    final categories = widget.categories == null
        ? const <Category>[]
        : await widget.categories!.allCategories();
    final accounts = widget.accounts == null
        ? const <AccountBalance>[]
        : await widget.accounts!.withBalances();
    final tags = await widget.repository.allTagNames();
    if (!mounted) return;
    setState(() {
      _categories = categories;
      _accounts = accounts;
      _tags = tags;
    });
  }

  Future<void> _run() async {
    setState(() => _searching = true);
    final result = await widget.repository.searchLedger(_filter);
    if (!mounted) return;
    setState(() {
      _result = result;
      _searching = false;
    });
  }

  void _apply(LedgerFilter next) {
    setState(() => _filter = next);
    _run();
  }

  void _onKeywordChanged(String value) {
    setState(() => _filter = _filterWith(keyword: value));
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 200), _run);
  }

  /// LedgerFilter 是 immutable，这里手写一个 copy 更直观（字段不多）。
  LedgerFilter _filterWith({
    String? keyword,
    EntryType? type,
    bool clearType = false,
    SearchRange? range,
    String? categoryId,
    bool clearCategory = false,
    String? accountId,
    bool clearAccount = false,
    String? tag,
    bool clearTag = false,
    int? minCents,
    bool clearMin = false,
    int? maxCents,
    bool clearMax = false,
  }) {
    return LedgerFilter(
      keyword: keyword ?? _filter.keyword,
      type: clearType ? null : (type ?? _filter.type),
      range: range ?? _filter.range,
      categoryId: clearCategory ? null : (categoryId ?? _filter.categoryId),
      accountId: clearAccount ? null : (accountId ?? _filter.accountId),
      tag: clearTag ? null : (tag ?? _filter.tag),
      minCents: clearMin ? null : (minCents ?? _filter.minCents),
      maxCents: clearMax ? null : (maxCents ?? _filter.maxCents),
    );
  }

  Future<void> _openFilters() async {
    final next = await showModalBottomSheet<LedgerFilter>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _FilterSheet(
        initial: _filter,
        categories: [
          for (final c in _categories)
            if (c.parentId == null) c,
        ],
        accounts: _accounts,
        tags: _tags,
      ),
    );
    if (next != null) _apply(next);
  }

  String? get _categoryName {
    final id = _filter.categoryId;
    if (id == null) return null;
    for (final c in _categories) {
      if (c.id == id) return c.name;
    }
    return null;
  }

  String? get _accountName {
    final id = _filter.accountId;
    if (id == null) return null;
    for (final a in _accounts) {
      if (a.account.id == id) return a.account.name;
    }
    return null;
  }

  Future<void> _openDetail(TransactionRow row) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => TransactionDetailPage(
          row: row,
          repository: widget.repository,
          attachments: widget.attachments,
          categories: _categories,
          accounts: _accounts,
          // 详情页也能补图：与记一笔用同一个选图实现（Web 无私有目录，禁掉）
          pickImage: kIsWeb ? null : systemImagePicker(),
        ),
      ),
    );
    // 详情里可能改了或删了，回来重查一次
    await _run();
  }

  @override
  Widget build(BuildContext context) {
    final palette = BeanPalette.of(context);
    final result = _result;

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
        titleSpacing: 0,
        title: TextField(
          controller: _keyword,
          autofocus: true,
          onChanged: _onKeywordChanged,
          textInputAction: TextInputAction.search,
          decoration: InputDecoration(
            isDense: true,
            hintText: '搜索备注 / 分类 / 账户 / 标签',
            hintStyle: TextStyle(fontSize: 15, color: palette.textSecondary),
            border: InputBorder.none,
          ),
          style: const TextStyle(fontSize: 16),
        ),
        actions: [
          IconButton(
            tooltip: '筛选',
            icon: const Icon(Icons.tune_rounded, size: 22),
            onPressed: _openFilters,
          ),
        ],
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _QuickFilters(
            filter: _filter,
            onChanged: _apply,
          ),
          _Summary(
            filter: _filter,
            categoryName: _categoryName,
            accountName: _accountName,
            onRemove: _apply,
          ),
          Padding(
            padding:
                const EdgeInsets.fromLTRB(BeanSpace.page, 4, BeanSpace.page, 8),
            child: Text(
              result == null
                  ? '搜索中…'
                  : result.truncated
                      ? '命中 ${result.matchedCount} 笔（只显示前 2000 笔，建议加条件）'
                      : '命中 ${result.matchedCount} 笔',
              style: TextStyle(fontSize: 12, color: palette.textSecondary),
            ),
          ),
          Expanded(
            child: _searching && result == null
                ? const SizedBox.shrink()
                : result == null || result.isEmpty
                    ? Center(
                        child: Text(
                          '没有匹配的账目',
                          style: TextStyle(
                            fontSize: 14,
                            color: palette.textSecondary,
                          ),
                        ),
                      )
                    : ListView(
                        padding: const EdgeInsets.only(bottom: 40),
                        children: [
                          LedgerDayList(
                            groups: result.groups,
                            attachments: widget.attachments,
                            onOpen: _openDetail,
                          ),
                        ],
                      ),
          ),
        ],
      ),
    );
  }
}

/// 收支类型 + 时间范围两排快捷胶囊。
class _QuickFilters extends StatelessWidget {
  const _QuickFilters({required this.filter, required this.onChanged});

  final LedgerFilter filter;
  final ValueChanged<LedgerFilter> onChanged;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: BeanSpace.page),
      child: Row(
        children: [
          _Chip(
            label: '全部收支',
            selected: filter.type == null,
            onTap: () => onChanged(
              LedgerFilter(
                keyword: filter.keyword,
                range: filter.range,
                categoryId: filter.categoryId,
                accountId: filter.accountId,
                tag: filter.tag,
                minCents: filter.minCents,
                maxCents: filter.maxCents,
              ),
            ),
          ),
          for (final type in EntryType.values)
            _Chip(
              label: switch (type) {
                EntryType.expense => '支出',
                EntryType.income => '收入',
                EntryType.transfer => '转账',
              },
              selected: filter.type == type,
              onTap: () => onChanged(
                LedgerFilter(
                  keyword: filter.keyword,
                  type: type,
                  range: filter.range,
                  categoryId: filter.categoryId,
                  accountId: filter.accountId,
                  tag: filter.tag,
                  minCents: filter.minCents,
                  maxCents: filter.maxCents,
                ),
              ),
            ),
          Container(
            width: BeanSpace.hairline,
            height: 18,
            margin: const EdgeInsets.symmetric(horizontal: 6),
            color: BeanPalette.of(context).border,
          ),
          for (final range in SearchRange.values)
            _Chip(
              label: range.label,
              selected: filter.range == range,
              onTap: () => onChanged(
                LedgerFilter(
                  keyword: filter.keyword,
                  type: filter.type,
                  range: range,
                  categoryId: filter.categoryId,
                  accountId: filter.accountId,
                  tag: filter.tag,
                  minCents: filter.minCents,
                  maxCents: filter.maxCents,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// 已生效的次要筛选：可单条移除，也可一键清空（关键词保留）。
class _Summary extends StatelessWidget {
  const _Summary({
    required this.filter,
    required this.categoryName,
    required this.accountName,
    required this.onRemove,
  });

  final LedgerFilter filter;
  final String? categoryName;
  final String? accountName;
  final ValueChanged<LedgerFilter> onRemove;

  @override
  Widget build(BuildContext context) {
    final chips = <Widget>[];
    if (categoryName != null) {
      chips.add(_Chip(
          label: categoryName!,
          selected: true,
          onTap: () => onRemove(_clear(category: true))));
    }
    if (accountName != null) {
      chips.add(_Chip(
          label: accountName!,
          selected: true,
          onTap: () => onRemove(_clear(account: true))));
    }
    if (filter.tag != null) {
      chips.add(_Chip(
          label: '#${filter.tag}',
          selected: true,
          onTap: () => onRemove(_clear(tag: true))));
    }
    if (filter.minCents != null || filter.maxCents != null) {
      final from =
          filter.minCents == null ? '' : '¥${formatCents(filter.minCents!)}';
      final to =
          filter.maxCents == null ? '' : '¥${formatCents(filter.maxCents!)}';
      chips.add(_Chip(
        label: '$from–$to',
        selected: true,
        onTap: () => onRemove(_clear(amount: true)),
      ));
    }
    if (chips.isEmpty) return const SizedBox(height: 6);

    final palette = BeanPalette.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(BeanSpace.page, 6, BeanSpace.page, 0),
      child: Row(
        children: [
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(children: chips),
            ),
          ),
          TextButton(
            onPressed: () => onRemove(filter.clearingFilters()),
            style: TextButton.styleFrom(
              visualDensity: VisualDensity.compact,
              foregroundColor: palette.textSecondary,
            ),
            child: const Text('清空筛选'),
          ),
        ],
      ),
    );
  }

  LedgerFilter _clear({
    bool category = false,
    bool account = false,
    bool tag = false,
    bool amount = false,
  }) {
    return LedgerFilter(
      keyword: filter.keyword,
      type: filter.type,
      range: filter.range,
      categoryId: category ? null : filter.categoryId,
      accountId: account ? null : filter.accountId,
      tag: tag ? null : filter.tag,
      minCents: amount ? null : filter.minCents,
      maxCents: amount ? null : filter.maxCents,
    );
  }
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
    return Padding(
      padding: const EdgeInsets.only(right: 8, top: 6, bottom: 6),
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          decoration: BoxDecoration(
            color: selected ? palette.goldDeep : palette.neutral.sand,
            borderRadius: BorderRadius.circular(9),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                label,
                style: TextStyle(
                  fontSize: 13,
                  color: selected
                      ? Theme.of(context).colorScheme.onPrimary
                      : palette.textSecondary,
                ),
              ),
              if (selected) ...[
                const SizedBox(width: 4),
                Icon(
                  Icons.close_rounded,
                  size: 13,
                  color: Theme.of(context).colorScheme.onPrimary,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// 「更多筛选」：分类 / 账户 / 标签 / 金额区间。
class _FilterSheet extends StatefulWidget {
  const _FilterSheet({
    required this.initial,
    required this.categories,
    required this.accounts,
    required this.tags,
  });

  final LedgerFilter initial;
  final List<Category> categories;
  final List<AccountBalance> accounts;
  final List<String> tags;

  @override
  State<_FilterSheet> createState() => _FilterSheetState();
}

class _FilterSheetState extends State<_FilterSheet> {
  late String? _categoryId = widget.initial.categoryId;
  late String? _accountId = widget.initial.accountId;
  late String? _tag = widget.initial.tag;
  late final TextEditingController _min = TextEditingController(
    text: widget.initial.minCents == null
        ? ''
        : formatCents(widget.initial.minCents!),
  );
  late final TextEditingController _max = TextEditingController(
    text: widget.initial.maxCents == null
        ? ''
        : formatCents(widget.initial.maxCents!),
  );

  @override
  void dispose() {
    _min.dispose();
    _max.dispose();
    super.dispose();
  }

  int? _parse(TextEditingController controller) {
    final text = controller.text.trim();
    if (text.isEmpty) return null;
    return parseAmountToCents(text);
  }

  void _apply() {
    Navigator.of(context).pop(
      LedgerFilter(
        keyword: widget.initial.keyword,
        type: widget.initial.type,
        range: widget.initial.range,
        categoryId: _categoryId,
        accountId: _accountId,
        tag: _tag,
        minCents: _parse(_min),
        maxCents: _parse(_max),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final palette = BeanPalette.of(context);
    return BeanSheet(
      title: '筛选',
      child: SizedBox(
        height: 420,
        child: Column(
          children: [
            // 条件区可滚：分类一多也不能把按钮顶出屏幕
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _label('分类', palette),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        _Chip(
                          label: '不限',
                          selected: _categoryId == null,
                          onTap: () => setState(() => _categoryId = null),
                        ),
                        for (final category in widget.categories)
                          _Chip(
                            label: category.name,
                            selected: _categoryId == category.id,
                            onTap: () =>
                                setState(() => _categoryId = category.id),
                          ),
                      ],
                    ),
                    _label('账户', palette),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        _Chip(
                          label: '不限',
                          selected: _accountId == null,
                          onTap: () => setState(() => _accountId = null),
                        ),
                        for (final account in widget.accounts)
                          _Chip(
                            label: account.account.name,
                            selected: _accountId == account.account.id,
                            onTap: () => setState(
                              () => _accountId = account.account.id,
                            ),
                          ),
                      ],
                    ),
                    if (widget.tags.isNotEmpty) _label('标签', palette),
                    if (widget.tags.isNotEmpty)
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          _Chip(
                            label: '不限',
                            selected: _tag == null,
                            onTap: () => setState(() => _tag = null),
                          ),
                          for (final tag in widget.tags)
                            _Chip(
                              label: '#$tag',
                              selected: _tag == tag,
                              onTap: () => setState(() => _tag = tag),
                            ),
                        ],
                      ),
                    _label('金额区间（元）', palette),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _min,
                            keyboardType: const TextInputType.numberWithOptions(
                              decimal: true,
                            ),
                            decoration: const InputDecoration(
                              labelText: '最小',
                              isDense: true,
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: TextField(
                            controller: _max,
                            keyboardType: const TextInputType.numberWithOptions(
                              decimal: true,
                            ),
                            decoration: const InputDecoration(
                              labelText: '最大',
                              isDense: true,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            // 操作行固定在底部：任何屏高都能点到「应用」
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 4),
              child: Row(
                children: [
                  const Spacer(),
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('取消'),
                  ),
                  const SizedBox(width: 4),
                  FilledButton(onPressed: _apply, child: const Text('应用')),
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
