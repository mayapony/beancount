import 'package:flutter/material.dart';

import '../data/db/app_database.dart';
import '../data/db/enums.dart';
import '../data/repositories/category_repository.dart';
import '../theme/tokens.dart';
import '../widgets/common.dart';

/// 图标候选：够用又不至于变成图标浏览器。
const _iconChoices = <String>[
  'restaurant',
  'directions_bus',
  'shopping_bag',
  'movie',
  'home',
  'medication',
  'school',
  'flight',
  'fitness_center',
  'devices',
  'pets',
  'delivery_dining',
  'local_cafe',
  'checkroom',
  'more_horiz',
];

/// 分类管理：支出/收入两套树，支持增、改名、换图标、排序、删除（带迁移）。
class CategoriesPage extends StatefulWidget {
  const CategoriesPage({super.key, required this.repository});

  final CategoryRepository repository;

  @override
  State<CategoriesPage> createState() => _CategoriesPageState();
}

class _CategoriesPageState extends State<CategoriesPage> {
  CategoryType _type = CategoryType.expense;
  List<Category> _categories = const [];
  Map<String, int> _counts = const {};
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  CategoryType get _categoryType => _type;

  Future<void> _reload() async {
    final all = await widget.repository.allCategories();
    final counts = await widget.repository.usageCounts();
    if (!mounted) return;
    setState(() {
      _categories = all;
      _counts = counts;
      _loading = false;
    });
  }

  List<Category> get _roots => [
        for (final c in _categories)
          if (c.type == _categoryType && c.parentId == null) c,
      ];

  List<Category> _childrenOf(String parentId) => [
        for (final c in _categories)
          if (c.parentId == parentId) c,
      ];

  int _usageOf(Category category) {
    var total = _counts[category.id] ?? 0;
    for (final child in _childrenOf(category.id)) {
      total += _counts[child.id] ?? 0;
    }
    return total;
  }

  Future<void> _openEditor({Category? category, String? parentId}) async {
    final result = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _CategoryEditor(
        repository: widget.repository,
        type: _categoryType,
        existing: category,
        initialParentId: parentId,
        roots: [
          for (final c in _categories)
            if (c.type == _categoryType && c.parentId == null) c,
        ],
      ),
    );
    if (result == true) await _reload();
  }

  Future<void> _confirmDelete(Category category) async {
    final used = await widget.repository.transactionCount(category.id);
    final childUsed = <String>[];
    for (final child in _childrenOf(category.id)) {
      final count = await widget.repository.transactionCount(child.id);
      if (count > 0) childUsed.add('${child.name}（$count 笔）');
    }

    if (used == 0 && childUsed.isEmpty) {
      await widget.repository.delete(category.id);
      if (!mounted) return;
      await _reload();
      return;
    }

    final targets = [
      for (final c in _categories)
        if (c.type == _categoryType &&
            c.id != category.id &&
            c.parentId != category.id)
          c,
    ];
    if (targets.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('没有可迁移的目标分类，先新建一个')),
      );
      return;
    }

    if (!mounted) return;
    final message = used > 0
        ? '「${category.name}」下有 $used 笔交易'
        : '子分类 ${childUsed.join('、')} 有交易';

    final target = await showModalBottomSheet<Category>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => _MigratePicker(
        title: '$message，迁移到…',
        targets: targets,
      ),
    );
    if (target == null) return;

    await widget.repository.migrateAndDelete(category.id, target.id);
    if (!mounted) return;
    await _reload();
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
          '分类',
          style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
        ),
        centerTitle: true,
        actions: [
          IconButton(
            tooltip: '新建分类',
            icon: const Icon(Icons.add_rounded, size: 24),
            onPressed: () => _openEditor(),
          ),
        ],
      ),
      body: _loading
          ? const SizedBox.shrink()
          : ListView(
              padding: const EdgeInsets.fromLTRB(0, 8, 0, 40),
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: BeanSpace.page,
                  ),
                  child: Row(
                    children: [
                      _TypeTab(
                        label: '支出分类',
                        selected: _type == CategoryType.expense,
                        onTap: () =>
                            setState(() => _type = CategoryType.expense),
                      ),
                      const SizedBox(width: 8),
                      _TypeTab(
                        label: '收入分类',
                        selected: _type == CategoryType.income,
                        onTap: () =>
                            setState(() => _type = CategoryType.income),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                for (final root in _roots) ...[
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: BeanSpace.page,
                      vertical: 2,
                    ),
                    child: BeanCard(
                      padding: EdgeInsets.zero,
                      child: Column(
                        children: [
                          _CategoryRow(
                            category: root,
                            usage: _usageOf(root),
                            onTap: () => _openEditor(category: root),
                            onDelete: () => _confirmDelete(root),
                            onAddChild: () => _openEditor(parentId: root.id),
                          ),
                          for (final child in _childrenOf(root.id))
                            _CategoryRow(
                              category: child,
                              usage: _counts[child.id] ?? 0,
                              indent: true,
                              onTap: () => _openEditor(category: child),
                              onDelete: () => _confirmDelete(child),
                            ),
                        ],
                      ),
                    ),
                  ),
                ],
                if (_roots.isEmpty)
                  Padding(
                    padding: const EdgeInsets.all(BeanSpace.page),
                    child: Text(
                      '还没有分类，点右上角 + 新建一个',
                      style: TextStyle(
                        fontSize: 13,
                        color: palette.textSecondary,
                      ),
                    ),
                  ),
              ],
            ),
    );
  }
}

class _TypeTab extends StatelessWidget {
  const _TypeTab({
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
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        decoration: BoxDecoration(
          color: selected ? palette.goldDeep : palette.neutral.sand,
          borderRadius: BorderRadius.circular(9),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 13,
            fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
            color: selected
                ? Theme.of(context).colorScheme.onPrimary
                : palette.textSecondary,
          ),
        ),
      ),
    );
  }
}

class _CategoryRow extends StatelessWidget {
  const _CategoryRow({
    required this.category,
    required this.usage,
    required this.onTap,
    required this.onDelete,
    this.onAddChild,
    this.indent = false,
  });

  final Category category;
  final int usage;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  /// 一级分类才有「加子分类」按钮。
  final VoidCallback? onAddChild;
  final bool indent;

  @override
  Widget build(BuildContext context) {
    final palette = BeanPalette.of(context);
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: EdgeInsets.fromLTRB(indent ? 34 : 16, 10, 8, 10),
        child: Row(
          children: [
            CategoryAvatar(
              name: category.name,
              colorValue: category.color,
              iconKey: category.icon,
              size: indent ? 26 : 32,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                category.name,
                style: TextStyle(
                  fontSize: indent ? 14 : 15,
                  fontWeight: indent ? FontWeight.w400 : FontWeight.w500,
                ),
              ),
            ),
            Text(
              usage == 0 ? '未使用' : '$usage 笔',
              style: TextStyle(fontSize: 12, color: palette.textSecondary),
            ),
            if (onAddChild != null)
              IconButton(
                tooltip: '加子分类',
                icon: const Icon(Icons.subdirectory_arrow_right_rounded,
                    size: 18),
                color: palette.textSecondary,
                onPressed: onAddChild,
              ),
            IconButton(
              tooltip: '删除',
              icon: const Icon(Icons.remove_circle_outline_rounded, size: 18),
              color: palette.alert,
              onPressed: onDelete,
            ),
          ],
        ),
      ),
    );
  }
}

/// 新建 / 编辑分类的面板。
class _CategoryEditor extends StatefulWidget {
  const _CategoryEditor({
    required this.repository,
    required this.type,
    required this.roots,
    this.existing,
    this.initialParentId,
  });

  final CategoryRepository repository;
  final CategoryType type;
  final List<Category> roots;
  final Category? existing;
  final String? initialParentId;

  @override
  State<_CategoryEditor> createState() => _CategoryEditorState();
}

class _CategoryEditorState extends State<_CategoryEditor> {
  late final TextEditingController _name =
      TextEditingController(text: widget.existing?.name ?? '');
  late String _icon = widget.existing?.icon ?? _iconChoices.first;
  late String? _parentId = widget.existing?.parentId ?? widget.initialParentId;
  String? _error;
  bool _saving = false;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  bool get _isNew => widget.existing == null;

  Future<void> _save() async {
    final name = _name.text.trim();
    if (name.isEmpty) {
      setState(() => _error = '分类名不能为空');
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
          type: widget.type,
          parentId: _parentId,
          icon: _icon,
        );
      } else {
        await widget.repository.rename(widget.existing!.id, name);
        await widget.repository.updateAppearance(
          widget.existing!.id,
          icon: _icon,
        );
      }
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } on DuplicateCategoryNameException catch (error) {
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

  Future<void> _move(int delta) async {
    await widget.repository.moveBy(widget.existing!.id, delta);
    if (!mounted) return;
    Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final palette = BeanPalette.of(context);

    return BeanSheet(
      title: _isNew ? '新建分类' : '编辑分类',
      child: SizedBox(
        // 面板内容比一屏高（输入框 + 归属 + 图标网格 + 按钮），必须能滚
        height: 420,
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
              if (_isNew) ...[
                const SizedBox(height: 14),
                Text(
                  '归属',
                  style: TextStyle(fontSize: 13, color: palette.textSecondary),
                ),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _Choice(
                      label: '一级分类',
                      selected: _parentId == null,
                      onTap: () => setState(() => _parentId = null),
                    ),
                    for (final root in widget.roots)
                      _Choice(
                        label: root.name,
                        selected: _parentId == root.id,
                        onTap: () => setState(() => _parentId = root.id),
                      ),
                  ],
                ),
              ],
              const SizedBox(height: 14),
              Text(
                '图标',
                style: TextStyle(fontSize: 13, color: palette.textSecondary),
              ),
              const SizedBox(height: 6),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final key in _iconChoices)
                    GestureDetector(
                      onTap: () => setState(() => _icon = key),
                      child: Container(
                        width: 38,
                        height: 38,
                        decoration: BoxDecoration(
                          color: _icon == key
                              ? palette.goldDeep.withValues(alpha: 0.16)
                              : palette.neutral.sand,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: _icon == key
                                ? palette.goldDeep
                                : Colors.transparent,
                          ),
                        ),
                        child: Icon(
                          categoryIconFor(key),
                          size: 19,
                          color: _icon == key
                              ? palette.goldDeep
                              : palette.textSecondary,
                        ),
                      ),
                    ),
                ],
              ),
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
                  if (!_isNew && widget.existing!.parentId == null) ...[
                    IconButton(
                      tooltip: '上移',
                      onPressed: _saving ? null : () => _move(-1),
                      icon: const Icon(Icons.arrow_upward_rounded, size: 20),
                    ),
                    IconButton(
                      tooltip: '下移',
                      onPressed: _saving ? null : () => _move(1),
                      icon: const Icon(Icons.arrow_downward_rounded, size: 20),
                    ),
                  ],
                  const Spacer(),
                  TextButton(
                    onPressed:
                        _saving ? null : () => Navigator.of(context).pop(),
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
      ),
    );
  }
}

class _Choice extends StatelessWidget {
  const _Choice({
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

/// 删除前迁移：只列出同类型、且不是自己或自己子级的目标。
class _MigratePicker extends StatelessWidget {
  const _MigratePicker({required this.title, required this.targets});

  final String title;
  final List<Category> targets;

  @override
  Widget build(BuildContext context) {
    final palette = BeanPalette.of(context);
    return BeanSheet(
      title: '迁移到',
      child: SizedBox(
        // 目标可能有十几个：固定高度 + 内部滚动，避免面板溢出
        height: 340,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(
                  title,
                  style: TextStyle(fontSize: 12, color: palette.textSecondary),
                ),
              ),
              for (final target in targets)
                InkWell(
                  onTap: () => Navigator.of(context).pop(target),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    child: Row(
                      children: [
                        CategoryAvatar(
                          name: target.name,
                          colorValue: target.color,
                          iconKey: target.icon,
                          size: 28,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            target.parentId == null
                                ? target.name
                                : '${target.name}（二级）',
                            style: const TextStyle(fontSize: 15),
                          ),
                        ),
                        Icon(
                          Icons.chevron_right_rounded,
                          size: 20,
                          color: palette.textSecondary,
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
