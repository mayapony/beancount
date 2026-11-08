import 'package:flutter/material.dart';

import '../data/category_library.dart';
import '../data/db/enums.dart';
import '../theme/category_icons.dart';
import '../theme/tokens.dart';
import '../widgets/common.dart';

/// 选中的结果：名字 + 需要一起建的父级名（一级分类没有父级）。
class CategoryPick {
  const CategoryPick(this.name, [this.parentName]);

  final String name;
  final String? parentName;
}

/// 新增分类：一个带搜索的分类库选择页。
///
/// 为什么是「整页」而不是弹窗：弹窗套在模态底部面板里时，Flutter 的文本输入
/// 连接会被两个焦点作用域扯住——真机上输入法弹得出来、候选词也有，但字就是
/// 不提交到输入框。整页有自己的焦点作用域，这个问题不存在。
class CategoryPickerPage extends StatefulWidget {
  const CategoryPickerPage({
    super.key,
    required this.title,
    required this.type,
    required this.existingNames,
    this.childOnly = false,
  });

  final String title;
  final CategoryType type;
  final Set<String> existingNames;

  /// 只列二级分类（从某个一级的二级区进来时）。
  final bool childOnly;

  @override
  State<CategoryPickerPage> createState() => _CategoryPickerPageState();
}

class _CategoryPickerPageState extends State<CategoryPickerPage> {
  final _controller = TextEditingController();
  final _focusNode = FocusNode();
  String _query = '';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _focusNode.requestFocus();
    });
  }

  @override
  void dispose() {
    _focusNode.dispose();
    _controller.dispose();
    super.dispose();
  }

  List<LibraryEntry> get _entries {
    final all = searchCategoryLibrary(_query, type: widget.type);
    if (!widget.childOnly) return all;
    return [
      for (final entry in all)
        if (entry.parent != null) entry,
    ];
  }

  bool get _canCreateCustom {
    final q = _query.trim();
    if (q.isEmpty) return false;
    if (widget.existingNames.contains(q)) return false;
    return !_entries.any((e) => e.category.name == q);
  }

  void _pick(CategoryPick pick) => Navigator.of(context).pop(pick);

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
        title: Text(
          widget.title,
          style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
        ),
        centerTitle: true,
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              BeanSpace.page,
              4,
              BeanSpace.page,
              8,
            ),
            child: TextField(
              key: const Key('category-add-field'),
              controller: _controller,
              focusNode: _focusNode,
              autofocus: true,
              textInputAction: TextInputAction.done,
              decoration: const InputDecoration(
                hintText: '搜索或输入名字',
                prefixIcon: Icon(Icons.search_rounded, size: 20),
                isDense: true,
              ),
              onChanged: (value) => setState(() => _query = value),
              onSubmitted: (_) {
                if (_canCreateCustom) _pick(CategoryPick(_query.trim()));
              },
            ),
          ),
          if (_canCreateCustom)
            Align(
              alignment: Alignment.centerLeft,
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: BeanSpace.page,
                ),
                child: TextButton.icon(
                  key: const Key('category-add-custom'),
                  onPressed: () => _pick(CategoryPick(_query.trim())),
                  icon: const Icon(Icons.add_rounded, size: 16),
                  label: Text('新建「${_query.trim()}」'),
                ),
              ),
            ),
          Expanded(
            child: _entries.isEmpty
                ? Center(
                    child: Text(
                      '没有匹配的分类，输入名字可直接新建',
                      style: TextStyle(
                        fontSize: 13,
                        color: palette.textSecondary,
                      ),
                    ),
                  )
                : ListView.builder(
                    itemCount: _entries.length,
                    itemBuilder: (context, index) {
                      final entry = _entries[index];
                      final exists =
                          widget.existingNames.contains(entry.category.name);
                      return ListTile(
                        key: Key('library-${entry.displayPath}'),
                        leading: Icon(
                          categoryIconFor(entry.category.iconKey),
                          size: 22,
                          color: palette.textSecondary,
                        ),
                        title: Row(
                          children: [
                            Text(entry.category.name),
                            if (entry.parent != null) ...[
                              const SizedBox(width: 8),
                              Text(
                                entry.parent!.name,
                                style: TextStyle(
                                  fontSize: 11,
                                  color: palette.textSecondary,
                                ),
                              ),
                            ],
                          ],
                        ),
                        trailing: exists
                            ? Text(
                                '已有',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: palette.textSecondary,
                                ),
                              )
                            : null,
                        enabled: !exists,
                        onTap: exists
                            ? null
                            : () => _pick(
                                  CategoryPick(
                                    entry.category.name,
                                    entry.parent?.name,
                                  ),
                                ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
