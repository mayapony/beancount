import 'dart:math' as math;

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../data/db/app_database.dart';
import '../data/db/enums.dart';
import '../data/repositories/account_repository.dart';
import '../theme/tokens.dart';
import '../utils/dates.dart';
import '../utils/money.dart';
import 'common.dart';

/// 一笔记账的草稿：面板的产出，交给仓储落库。
@immutable
class QuickEntryDraft {
  const QuickEntryDraft({
    required this.amount,
    required this.isIncome,
    this.isTransfer = false,
    this.category,
    this.account,
    this.toAccount,
    required this.time,
    this.note = '',
    this.tags = const <String>[],
  });

  final double amount;
  final bool isIncome;

  /// 转账：没有分类，`account` 为转出、`toAccount` 为转入。
  final bool isTransfer;

  /// 选中的分类记录（一级或二级），落库时直接取 `id`；转账时为 null。
  final Category? category;
  final Account? account;
  final Account? toAccount;
  final DateTime time;
  final String note;
  final List<String> tags;
}

/// 记一笔面板 —— 金豆按下直接进入，一次点击开始输入。
///
/// 结构（参照成熟记账 App，见 docs/review/记账面板-设计评审.md）：
/// 标题 + 支出/收入分段 → 分类（4 列 × 3 行，灰阶 + 金色实心选中）
/// → 账户/时间 → 金额卡（金额 + 备注行：图片 / 相机 / 标签）→ 键盘（贴底，不随内容滚动）。
///
/// 三条视觉规则：
/// 1. 同屏只有一个强调色：只有"选中分类 + 完成"用 `goldDeep`；
/// 2. 键盘白键必须压在 `neutral.sand` 底座上，键的边界才看得见；
/// 3. 金额是唯一的大字号，其余文字一律 ≤15px。
class QuickEntrySheet extends StatefulWidget {
  const QuickEntrySheet({
    super.key,
    required this.onSubmit,
    required this.categories,
    required this.accounts,
    this.initialCategoryId,
    this.initialIsIncome = false,
    this.initialAccountId,
    this.initialDraft,
    this.recentNotes = const <String>[],
  });

  /// 全部分类（一级与二级都在内）；面板按当前收支类型过滤后展示。
  final List<Category> categories;

  /// 全部账户（含推导出来的余额），面板只负责选，不负责建。
  final List<AccountBalance> accounts;

  /// 分类/类型/账户继承上次记账的值（DESIGN.md §9.1：无需重选）。
  final String? initialCategoryId;
  final bool initialIsIncome;
  final String? initialAccountId;

  /// 编辑模式：以这笔交易的现值预填面板。为空时是新增模式，行为不变。
  final QuickEntryDraft? initialDraft;

  /// 最近用过的备注（壳层查好传进来）：备注弹窗里作为一键填充。
  final List<String> recentNotes;

  /// 提交回调：返回 null 表示保存成功，返回字符串表示失败原因（面板保持打开）。
  final Future<String?> Function(QuickEntryDraft draft) onSubmit;

  @override
  State<QuickEntrySheet> createState() => _QuickEntrySheetState();
}

/// 标签预设（M0 先用固定集合，等标签模型落地再改成用户自建）。
const kQuickTagPresets = <String>[
  '出差',
  '报销',
  '聚餐',
  '礼物',
  '家庭',
  '旅行',
  '工作',
  '理财',
];

/// 键盘尺寸：4 行 × 56 + 3 道 8 的缝 + 上下 8 的内边距。
const double _kKeyHeight = 56;
const double _kKeyGap = 8;

/// 强调色实心填充：亮色用 `goldDeep`（白字 5:1），
/// 暗色用 `goldDark`（深字 5.4:1）；若用浅金 + 白字会掉到 2:1。
Color _accentFill(BuildContext context) =>
    Theme.of(context).brightness == Brightness.dark
        ? BeanColors.goldDark
        : BeanColors.goldDeep;

Color _onAccentFill(BuildContext context) =>
    Theme.of(context).brightness == Brightness.dark
        ? BeanColors.textLight
        : Colors.white;

class _QuickEntrySheetState extends State<QuickEntrySheet>
    with SingleTickerProviderStateMixin {
  late bool _isIncome = widget.initialDraft?.isIncome ?? widget.initialIsIncome;

  /// 转账模式：分类网格换成「从 / 到」两个账户。
  late bool _isTransfer = widget.initialDraft?.isTransfer ?? false;

  /// 当前选中的分类 id；为空或与当前类型不匹配时回落到第一个可见分类。
  late String? _categoryId =
      widget.initialDraft?.category?.id ?? widget.initialCategoryId;

  /// 面板只展示一级分类，并按当前收支类型过滤。
  List<Category> get _visibleCategories => [
        for (final c in widget.categories)
          if (c.parentId == null &&
              c.type ==
                  (_isIncome ? CategoryType.income : CategoryType.expense))
            c,
      ];

  Category? get _selectedCategory {
    final id = _categoryId;
    if (id != null) {
      // 精确匹配优先：编辑一笔二级分类的账时不能把它悄悄改成一级父类
      for (final c in widget.categories) {
        if (c.id == id &&
            c.type ==
                (_isIncome ? CategoryType.income : CategoryType.expense)) {
          return c;
        }
      }
    }
    final visible = _visibleCategories;
    return visible.isEmpty ? null : visible.first;
  }

  /// 网格高亮用：二级分类高亮它所属的一级父类（网格里只有一级）。
  Category? get _highlightCategory {
    final selected = _selectedCategory;
    if (selected == null || selected.parentId == null) return selected;
    for (final c in widget.categories) {
      if (c.id == selected.parentId) return c;
    }
    return selected;
  }

  /// 当前选中的账户；上次的账户被删了就回落到第一个。
  AccountBalance? get _selectedAccount {
    for (final a in widget.accounts) {
      if (a.account.id == _accountId) return a;
    }
    return widget.accounts.isEmpty ? null : widget.accounts.first;
  }

  /// 转账的「到」账户：默认取与「从」不同的第一个账户。
  AccountBalance? get _selectedToAccount {
    for (final a in widget.accounts) {
      if (a.account.id == _toAccountId) return a;
    }
    for (final a in widget.accounts) {
      if (a.account.id != _selectedAccount?.account.id) return a;
    }
    return null;
  }

  bool get _transferAccountsValid {
    final from = _selectedAccount?.account.id;
    final to = _selectedToAccount?.account.id;
    return from != null && to != null && from != to;
  }

  late String _amount = _initialAmountText();

  /// 编辑模式下的金额回填：38.50 → '38.5'，45.00 → '45'
  String _initialAmountText() {
    final draft = widget.initialDraft;
    if (draft == null) return '0';
    final text = draft.amount.toStringAsFixed(2);
    if (text.endsWith('.00')) return text.substring(0, text.length - 3);
    if (text.endsWith('0')) return text.substring(0, text.length - 1);
    return text;
  }

  /// 待计算的左操作数（支持 38.5 + 12 这类连续计算）
  double? _left;
  String? _op;

  late String _note = widget.initialDraft?.note ?? '';
  late final Set<String> _tags = <String>{...?widget.initialDraft?.tags};

  /// 账户与时间：都继承上次值，点胶囊可改。
  late String? _accountId =
      widget.initialDraft?.account?.id ?? widget.initialAccountId;

  /// 转账的转入账户。
  late String? _toAccountId = widget.initialDraft?.toAccount?.id;
  late DateTime _time = widget.initialDraft?.time ?? DateTime.now();

  /// 保存中：按钮暂时禁用，避免重复提交
  bool _saving = false;

  /// 保存失败原因，显示在金额卡的操作行位置
  String? _errorText;

  /// 图片识别中
  bool _recognizing = false;

  /// 「再记」后的内联反馈（SnackBar 会被 modal sheet 挡住，所以自己画）
  late final AnimationController _toast;
  String _toastText = '';

  @override
  void initState() {
    super.initState();
    _toast = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    );
    // 播完自动归零，备注行回到「点击填写备注」
    _toast.addStatusListener((status) {
      if (status == AnimationStatus.completed && mounted) {
        setState(_toast.reset);
      }
    });
  }

  @override
  void dispose() {
    _toast.dispose();
    super.dispose();
  }

  double get _value => double.tryParse(_amount) ?? 0;

  double get _finalValue =>
      _op == null ? _value : _apply(_left ?? 0, _op!, _value);

  bool get _canSubmit =>
      _finalValue > 0 &&
      (_isTransfer ? _transferAccountsValid : _selectedCategory != null);

  double _apply(double a, String op, double b) {
    if (op == '+') return a + b;
    if (op == '−') return a - b;
    return b;
  }

  void _appendDigit(String digit) {
    if (_amount.contains('.') && _amount.split('.')[1].length >= 2) return;
    _amount = _amount == '0' ? digit : '$_amount$digit';
  }

  void _press(String key) {
    HapticFeedback.selectionClick();
    setState(() {
      _errorText = null;
      if (key == '⌫') {
        _amount = _amount.length <= 1
            ? '0'
            : _amount.substring(0, _amount.length - 1);
      } else if (key == '.') {
        if (!_amount.contains('.')) _amount = '$_amount.';
      } else {
        _appendDigit(key);
      }
    });
  }

  void _pressOperator(String op) {
    HapticFeedback.selectionClick();
    setState(() {
      if (_op == null) {
        _left = _value;
        _op = op;
        _amount = '0';
      } else if (op == _op && _amount == '0') {
        // 重复点同一个运算符：取消待计算
        _op = null;
        _left = null;
      } else {
        _left = _apply(_left ?? 0, _op!, _value);
        _op = op;
        _amount = '0';
      }
    });
  }

  /// 图片入口：上传即识别（当前为交互骨架，M7 替换为真实视觉模型）
  Future<void> _recognizeBill() async {
    setState(() => _recognizing = true);
    await Future<void>.delayed(const Duration(milliseconds: 900));
    if (!mounted) return;
    setState(() {
      _recognizing = false;
      _amount = '38.50';
      _categoryId = null;
      _isIncome = false;
      _left = null;
      _op = null;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('已识别：¥38.50 · 餐饮（M7 接入真实视觉模型）'),
      ),
    );
  }

  /// 备注：用弹窗编辑，避免系统键盘顶掉自定义数字键盘。
  ///
  /// 弹窗里给「最近用过」的备注（来自真实历史），点一下就填上。
  Future<void> _editNote() async {
    final result = await showDialog<String>(
      context: context,
      builder: (_) => _NoteDialog(
        initial: _note,
        recentNotes: widget.recentNotes,
      ),
    );
    if (result == null || !mounted) return;
    setState(() => _note = result.trim());
  }

  /// 标签：预设多选，选中的标签会以 # 前缀显示在备注行。
  Future<void> _editTags() async {
    final picked = <String>{..._tags};
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text(
            '标签',
            style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
          ),
          content: SizedBox(
            width: 280,
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final tag in kQuickTagPresets)
                  FilterChip(
                    label: Text(tag),
                    selected: picked.contains(tag),
                    showCheckmark: false,
                    selectedColor: BeanColors.gold.withValues(alpha: 0.16),
                    side: BorderSide(
                      color: picked.contains(tag)
                          ? BeanColors.gold
                          : Theme.of(ctx).colorScheme.outline,
                    ),
                    labelStyle: TextStyle(
                      fontSize: 13,
                      fontWeight: picked.contains(tag)
                          ? FontWeight.w600
                          : FontWeight.w400,
                      color: picked.contains(tag)
                          ? BeanColors.goldDeep
                          : BeanPalette.of(ctx).textSecondary,
                    ),
                    onSelected: (selected) => setDialogState(() {
                      if (selected) {
                        picked.add(tag);
                      } else {
                        picked.remove(tag);
                      }
                    }),
                  ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('确定'),
            ),
          ],
        ),
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() {
      _tags
        ..clear()
        ..addAll(picked);
    });
  }

  Future<void> _submit({bool keepOpen = false}) async {
    if (!_canSubmit || _saving) return;
    final draft = QuickEntryDraft(
      amount: _finalValue,
      isIncome: _isTransfer ? false : _isIncome,
      isTransfer: _isTransfer,
      category: _isTransfer ? null : _selectedCategory,
      account: _selectedAccount?.account,
      toAccount: _isTransfer ? _selectedToAccount?.account : null,
      time: _time,
      note: _note,
      tags: List<String>.unmodifiable(_tags),
    );
    HapticFeedback.lightImpact();
    setState(() {
      _saving = true;
      _errorText = null;
    });

    // 落库失败（或命中去重）时面板保持打开，输入一律不动
    final String? error = await widget.onSubmit(draft);
    if (!mounted) return;
    if (error != null) {
      setState(() {
        _saving = false;
        _errorText = error;
      });
      return;
    }

    setState(() => _saving = false);
    if (keepOpen) {
      final summary = _isTransfer
          ? '已记 转账 ¥${formatMoney(_finalValue)}'
          : '已记 ${_isIncome ? '+' : '-'}¥${formatMoney(_finalValue)} · '
              '${_selectedCategory?.name ?? ''}';
      setState(() {
        _amount = '0';
        _left = null;
        _op = null;
        _note = '';
        _tags.clear();
        _time = DateTime.now();
        _toastText = summary;
      });
      _toast.forward(from: 0);
    } else {
      Navigator.of(context).pop();
    }
  }

  /// 账户选择：底部小面板，选中即返回。[to] 为 true 时选的是转入账户。
  Future<void> _pickAccount({bool to = false}) async {
    final picked = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: BeanPalette.of(context).surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => _AccountSheet(
        accounts: widget.accounts,
        selectedId: to ? _toAccountId : _accountId,
      ),
    );
    if (picked == null || !mounted) return;
    setState(() {
      if (to) {
        _toAccountId = picked;
      } else {
        _accountId = picked;
      }
    });
  }

  /// 时间选择：快捷「今天/昨天/前天」+ 日期时间滚轮。
  Future<void> _pickTime() async {
    final picked = await showModalBottomSheet<DateTime>(
      context: context,
      backgroundColor: BeanPalette.of(context).surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => _TimeSheet(initial: _time),
    );
    if (picked == null || !mounted) return;
    setState(() => _time = picked);
  }

  @override
  Widget build(BuildContext context) {
    final palette = BeanPalette.of(context);
    final neutral = palette.neutral;
    final safeBottom = math.min(
      MediaQuery.viewPaddingOf(context).bottom,
      28.0,
    );

    return ConstrainedBox(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * 0.96,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // ── 拖拽条 + 标题栏：一个标题、一个关闭按钮 ──────────
          const SizedBox(height: 8),
          Container(
            width: 36,
            height: 4,
            decoration: BoxDecoration(
              color: neutral.handle,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          SizedBox(
            // 44 的触控高度 + 上下各 3 的呼吸
            height: 50,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 3, 12, 3),
              child: Row(
                children: [
                  Text(
                    widget.initialDraft == null ? '记一笔' : '编辑一笔',
                    style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                      color: Theme.of(context).colorScheme.onSurface,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _Segmented(
                      mode: _isTransfer ? 2 : (_isIncome ? 1 : 0),
                      onChanged: (mode) => setState(() {
                        _isTransfer = mode == 2;
                        _isIncome = mode == 1;
                        if (_isTransfer && _toAccountId == null) {
                          _toAccountId = _selectedToAccount?.account.id;
                        }
                      }),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    tooltip: '关闭',
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close_rounded, size: 20),
                    style: IconButton.styleFrom(
                      backgroundColor: neutral.sand,
                      foregroundColor: palette.textSecondary,
                      minimumSize: const Size(40, 40),
                      padding: EdgeInsets.zero,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 6),

          // ── 转账：没有分类，改成「从 / 到」两个账户 ─────────────
          if (_isTransfer)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Column(
                children: [
                  _TransferAccountChip(
                    label: '从',
                    accountName: _selectedAccount?.account.name ?? '选择账户',
                    onTap: () => _pickAccount(),
                  ),
                  const SizedBox(height: 8),
                  _TransferAccountChip(
                    label: '到',
                    accountName: _selectedToAccount?.account.name ?? '选择账户',
                    onTap: () => _pickAccount(to: true),
                  ),
                ],
              ),
            )
          else
            // ── 分类：4 列网格，首屏 3 行（12 个）；分类更多时内部滚动 ──
            Flexible(
              fit: FlexFit.loose,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 222),
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final visible = _visibleCategories;
                    final selected = _highlightCategory;
                    if (visible.isEmpty) {
                      return SizedBox(
                        height: 74,
                        child: Center(
                          child: Text(
                            '还没有分类',
                            style: TextStyle(
                              fontSize: 13,
                              color: palette.textSecondary,
                            ),
                          ),
                        ),
                      );
                    }
                    final rows = (visible.length / 4).ceil();
                    final grid = SingleChildScrollView(
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.start,
                        children: [
                          for (var row = 0; row < rows; row++)
                            Row(
                              children: [
                                for (var col = 0; col < 4; col++)
                                  Expanded(
                                    child: row * 4 + col < visible.length
                                        ? _CategoryCell(
                                            category: visible[row * 4 + col],
                                            selected: selected?.id ==
                                                visible[row * 4 + col].id,
                                            onTap: () {
                                              HapticFeedback.selectionClick();
                                              setState(() {
                                                _categoryId =
                                                    visible[row * 4 + col].id;
                                              });
                                            },
                                          )
                                        : const SizedBox(height: 74),
                                  ),
                              ],
                            ),
                        ],
                      ),
                    );
                    // 只有分类超过 3 行（需要滚动）时才加底部淡出：
                    // 提示"还能滑"，而不是看起来被裁掉
                    if (rows <= 3) return grid;
                    return ShaderMask(
                      blendMode: BlendMode.dstIn,
                      shaderCallback: (rect) => const LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.white,
                          Colors.white,
                          Colors.transparent
                        ],
                        stops: [0.0, 0.93, 1.0],
                      ).createShader(rect),
                      child: grid,
                    );
                  },
                ),
              ),
            ),
          const SizedBox(height: 6),

          // ── 元信息：时间（转账时账户已在上面选好）────────────────
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                if (!_isTransfer) ...[
                  Flexible(
                    child: _MetaChip(
                      icon: Icons.account_balance_wallet_rounded,
                      label: _selectedAccount?.account.name ?? '不选账户',
                      onTap: () => _pickAccount(),
                    ),
                  ),
                  const SizedBox(width: 8),
                ],
                _MetaChip(
                  icon: Icons.schedule_rounded,
                  label: formatEntryTime(_time),
                  onTap: _pickTime,
                ),
                if (_isTransfer) const Spacer(),
              ],
            ),
          ),
          const SizedBox(height: 10),

          // ── 金额 + 备注：一个输入区，备注行安放图片/相机/标签 ──
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Container(
              padding: const EdgeInsets.fromLTRB(16, 10, 8, 6),
              decoration: BoxDecoration(
                color: palette.surface,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: neutral.lineStrong),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 运算过程固定占 18px：输入 + 时卡片不会突然变高。
                  // 出错时同一行改显示原因（红色），不额外占高度。
                  SizedBox(
                    height: 18,
                    child: _errorText != null
                        ? Align(
                            alignment: Alignment.bottomLeft,
                            child: Text(
                              _errorText!,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 13,
                                height: 1.15,
                                color: BeanColors.alertRed,
                              ),
                            ),
                          )
                        : (_op == null
                            ? null
                            : Align(
                                alignment: Alignment.bottomLeft,
                                child: Text(
                                  '${formatMoneyCompact(_left ?? 0)} $_op',
                                  style: TextStyle(
                                    fontSize: 13,
                                    height: 1.15,
                                    color: palette.textSecondary,
                                    fontFeatures: const [
                                      FontFeature.tabularFigures(),
                                    ],
                                  ),
                                ),
                              )),
                  ),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.baseline,
                    textBaseline: TextBaseline.alphabetic,
                    children: [
                      Text(
                        '¥',
                        style: TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.w600,
                          color: _isTransfer
                              ? palette.transfer
                              : (_isIncome ? palette.income : palette.expense),
                        ),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        _amount.contains('.')
                            ? _amount
                            : '${_amount == '0' ? '0' : _amount}.00',
                        style: TextStyle(
                          fontSize: 42,
                          height: 1.15,
                          fontWeight: FontWeight.w700,
                          color: _isTransfer
                              ? palette.transfer
                              : (_isIncome ? palette.income : palette.expense),
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                      // 输入光标：让人看出「这里在等我打字」
                      Container(
                        width: 2,
                        height: 28,
                        margin: const EdgeInsets.only(left: 2, bottom: 6),
                        color: BeanColors.gold,
                      ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Row(
                    children: [
                      Expanded(
                        child: GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: _editNote,
                          child: SizedBox(
                            height: 44,
                            child: Align(
                              alignment: Alignment.centerLeft,
                              child: _statusLine(palette),
                            ),
                          ),
                        ),
                      ),
                      if (_recognizing)
                        const Padding(
                          padding: EdgeInsets.only(right: 4),
                          child: SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: BeanColors.goldDeep,
                            ),
                          ),
                        )
                      else ...[
                        _NoteAction(
                          icon: Icons.image_outlined,
                          tooltip: '从相册识别',
                          onTap: _recognizeBill,
                        ),
                        _NoteAction(
                          icon: Icons.photo_camera_outlined,
                          tooltip: '拍照识别',
                          onTap: _recognizeBill,
                        ),
                        _NoteAction(
                          icon: Icons.sell_outlined,
                          tooltip: '选择标签',
                          highlighted: _tags.isNotEmpty,
                          onTap: _editTags,
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 10),

          // ── 键盘：砂色底座 + 白键，永远贴底 ─────────────────
          Container(
            color: neutral.sand,
            padding: EdgeInsets.fromLTRB(8, 8, 8, 8 + safeBottom),
            child: Column(
              children: [
                _digitRow(
                  const ['1', '2', '3'],
                  _functionKey(
                    icon: Icons.backspace_outlined,
                    onTap: () => _press('⌫'),
                  ),
                ),
                _digitRow(const ['4', '5', '6'], _operatorKey('+')),
                _digitRow(const ['7', '8', '9'], _operatorKey('−')),
                Row(
                  children: [
                    Expanded(
                      child: _SurfaceKey(
                        onTap: () => _submit(keepOpen: true),
                        enabled: _canSubmit && !_saving,
                        child: Text(
                          '再记',
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                            color: _canSubmit
                                ? BeanColors.goldDeep
                                : neutral.disabledFg,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: _kKeyGap),
                    Expanded(child: _digitKey('0')),
                    const SizedBox(width: _kKeyGap),
                    Expanded(child: _dotKey()),
                    const SizedBox(width: _kKeyGap),
                    Expanded(
                      child: _SurfaceKey(
                        filled: true,
                        enabled: _canSubmit && !_saving,
                        onTap: _submit,
                        child: Text(
                          '完成',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: _canSubmit
                                ? _onAccentFill(context)
                                : neutral.disabledFg,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// 备注行的状态行：平时显示备注/标签，「再记」后短暂显示记账确认。
  Widget _statusLine(BeanPalette palette) {
    return AnimatedBuilder(
      animation: _toast,
      builder: (context, _) {
        final v = _toast.value;
        if (v == 0) return _noteLine(palette);
        final fade = v < 0.08 ? v / 0.08 : (v > 0.9 ? (1 - v) / 0.1 : 1.0);
        return Opacity(
          opacity: fade.clamp(0.0, 1.0),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.check_circle_rounded,
                size: 15,
                color: BeanColors.beanGreenDeep,
              ),
              const SizedBox(width: 5),
              Text(
                _toastText,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: BeanColors.beanGreenDeep,
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _noteLine(BeanPalette palette) {
    final primary = Theme.of(context).colorScheme.onSurface;
    final tagText = _tags.map((t) => '#$t').join(' ');
    return Text.rich(
      TextSpan(
        children: [
          if (tagText.isNotEmpty)
            TextSpan(
              text: tagText,
              style: TextStyle(
                color: BeanColors.goldDeep,
                fontWeight: FontWeight.w600,
              ),
            ),
          if (tagText.isNotEmpty && _note.isNotEmpty)
            const TextSpan(text: '  '),
          TextSpan(
            text: _note.isEmpty ? '点击填写备注' : _note,
            style: TextStyle(
              color: _note.isEmpty ? palette.textSecondary : primary,
            ),
          ),
        ],
      ),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: const TextStyle(fontSize: 13),
    );
  }

  Widget _digitKey(String digit) => _SurfaceKey(
        onTap: () => _press(digit),
        child: Text(
          digit,
          style: TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.w600,
            color: Theme.of(context).colorScheme.onSurface,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
      );

  Widget _dotKey() => _SurfaceKey(
        onTap: () => _press('.'),
        child: Text(
          '.',
          style: TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.w600,
            color: BeanPalette.of(context).textSecondary,
          ),
        ),
      );

  Widget _functionKey({required IconData icon, required VoidCallback onTap}) =>
      _SurfaceKey(
        onTap: onTap,
        child: Icon(
          icon,
          size: 21,
          color: BeanPalette.of(context).textSecondary,
        ),
      );

  Widget _operatorKey(String op) {
    final active = _op == op;
    return _SurfaceKey(
      onTap: () => _pressOperator(op),
      tint: active ? BeanColors.gold.withValues(alpha: 0.16) : null,
      child: Text(
        op,
        style: TextStyle(
          fontSize: 22,
          fontWeight: FontWeight.w600,
          color: active
              ? BeanColors.goldDeep
              : BeanPalette.of(context).textSecondary,
        ),
      ),
    );
  }

  Widget _digitRow(List<String> digits, Widget right) {
    return Padding(
      padding: const EdgeInsets.only(bottom: _kKeyGap),
      child: Row(
        children: [
          for (final digit in digits) ...[
            Expanded(child: _digitKey(digit)),
            const SizedBox(width: _kKeyGap),
          ],
          Expanded(child: right),
        ],
      ),
    );
  }
}

/// 分段控件：类型是"背景状态"，用轻量胶囊，不抢主按钮的语法。
/// 视觉 34 高、热区 44 高：胶囊够轻，手指够得着，语义（button/selected）也保留在可点层上。
class _Segmented extends StatelessWidget {
  const _Segmented({required this.mode, required this.onChanged});

  /// 0 = 支出、1 = 收入、2 = 转账。
  final int mode;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final neutral = BeanPalette.of(context).neutral;
    final labels = const ['支出', '收入', '转账'];
    return SizedBox(
      height: 44,
      child: Stack(
        children: [
          // 轨道（不可点）
          Positioned.fill(
            top: 5,
            bottom: 5,
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: neutral.track,
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
            ),
          ),
          Positioned.fill(
            child: Row(
              // stretch：让分段拿到 44 的紧凑高度，胶囊才能正确内缩
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (var i = 0; i < labels.length; i++)
                  _segment(context, labels[i], mode == i, () => onChanged(i)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _segment(
    BuildContext context,
    String label,
    bool selected,
    VoidCallback onTap,
  ) {
    final neutral = BeanPalette.of(context).neutral;
    return Expanded(
      child: Semantics(
        button: true,
        selected: selected,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: Stack(
            alignment: Alignment.center,
            children: [
              Positioned(
                top: 8,
                bottom: 8,
                left: 3,
                right: 3,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  decoration: BoxDecoration(
                    color: selected ? neutral.raised : Colors.transparent,
                    borderRadius: BorderRadius.circular(8),
                    boxShadow: selected
                        ? const [
                            BoxShadow(
                              color: Color(0x0F1C1917),
                              blurRadius: 4,
                              offset: Offset(0, 1),
                            ),
                          ]
                        : null,
                  ),
                ),
              ),
              Text(
                label,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                  color: selected
                      ? BeanColors.goldDeep
                      : BeanPalette.of(context).textSecondary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 分类格：未选中 = 砂色圆 + 暖灰图标；选中 = 金色实心圆 + 白图标。
/// 12 个分类同屏时，颜色是噪声，选中项才是信息。
class _CategoryCell extends StatelessWidget {
  const _CategoryCell({
    required this.category,
    required this.selected,
    required this.onTap,
  });

  final Category category;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = BeanPalette.of(context);
    final neutral = palette.neutral;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: SizedBox(
        height: 74,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: selected ? _accentFill(context) : neutral.sand,
              ),
              child: Icon(
                categoryIconFor(category.icon),
                size: 22,
                color: selected ? _onAccentFill(context) : neutral.iconNeutral,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              category.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 12,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                color: selected ? BeanColors.goldDeep : palette.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 元信息胶囊：40px 高、实底、正向文案。
class _MetaChip extends StatelessWidget {
  const _MetaChip({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = BeanPalette.of(context);
    return Material(
      color: palette.neutral.sand,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onTap,
        child: SizedBox(
          height: 44,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 16, color: palette.textSecondary),
                const SizedBox(width: 6),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: palette.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 备注行右侧的小动作（图片 / 相机 / 标签），44×44 热区。
class _NoteAction extends StatelessWidget {
  const _NoteAction({
    required this.icon,
    required this.tooltip,
    required this.onTap,
    this.highlighted = false,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;
  final bool highlighted;

  @override
  Widget build(BuildContext context) {
    final palette = BeanPalette.of(context);
    final color = highlighted ? BeanColors.goldDeep : palette.textSecondary;
    return SizedBox(
      width: 44,
      height: 44,
      child: IconButton(
        tooltip: tooltip,
        onPressed: onTap,
        icon: Icon(icon, size: 20),
        color: color,
        padding: EdgeInsets.zero,
        constraints: const BoxConstraints.tightFor(width: 44, height: 44),
        splashRadius: 22,
      ),
    );
  }
}

/// 键帽：白键压在砂色底座上；`filled` 用于主按钮，禁用态有独立配色。
class _SurfaceKey extends StatelessWidget {
  const _SurfaceKey({
    required this.child,
    this.onTap,
    this.filled = false,
    this.enabled = true,
    this.tint,
  });

  final Widget child;
  final VoidCallback? onTap;
  final bool filled;
  final bool enabled;
  final Color? tint;

  @override
  Widget build(BuildContext context) {
    final palette = BeanPalette.of(context);
    final neutral = palette.neutral;
    // 键帽用"抬升面"：亮色白、暗色比砂色底座更亮；半透明 tint 先混到底色上
    final keyColor =
        tint == null ? neutral.raised : Color.alphaBlend(tint!, neutral.raised);
    return Material(
      color: filled
          ? (enabled ? _accentFill(context) : neutral.disabledBg)
          : (enabled ? keyColor : neutral.disabledBg),
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: enabled ? onTap : null,
        child: SizedBox(
          height: _kKeyHeight,
          child: Center(child: child),
        ),
      ),
    );
  }
}

/// 选择账户：一行一个，选中打钩；金额带符号（信用卡欠款用警示色）。
class _AccountSheet extends StatelessWidget {
  const _AccountSheet({required this.accounts, required this.selectedId});

  final List<AccountBalance> accounts;
  final String? selectedId;

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

  @override
  Widget build(BuildContext context) {
    final palette = BeanPalette.of(context);
    return BeanSheet(
      title: '选择账户',
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: Column(
          children: [
            for (final item in accounts)
              Material(
                color: Colors.transparent,
                child: InkWell(
                  borderRadius: BorderRadius.circular(12),
                  onTap: () => Navigator.of(context).pop(item.account.id),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                    child: Row(
                      children: [
                        _AccountDot(type: item.account.type, size: 36),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                item.account.name,
                                style: const TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                _typeLabel(item.account.type),
                                style: TextStyle(
                                  fontSize: 12,
                                  color: palette.textSecondary,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Text(
                          // 金额统一两位小数；负号放在 ¥ 前面，读作"欠 ¥3,280.40"
                          '${item.balanceCents < 0 ? '-' : ''}'
                          '¥${formatMoney(item.balanceCents.abs() / 100)}',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: item.balanceCents < 0
                                ? palette.alert
                                : palette.expense,
                            fontFeatures: const [
                              FontFeature.tabularFigures(),
                            ],
                          ),
                        ),
                        const SizedBox(width: 10),
                        SizedBox(
                          width: 20,
                          child: item.account.id == selectedId
                              ? const Icon(
                                  Icons.check_circle_rounded,
                                  size: 20,
                                  color: BeanColors.goldDeep,
                                )
                              : null,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// 账户圆点：颜色按类型固定，和资产页保持一致。
class _AccountDot extends StatelessWidget {
  const _AccountDot({required this.type, this.size = 30});

  final AccountType type;
  final double size;

  @override
  Widget build(BuildContext context) {
    final (color, icon) = switch (type) {
      AccountType.wallet => (
          BeanColors.gold,
          Icons.account_balance_wallet_rounded
        ),
      AccountType.debit => (const Color(0xFF3B82F6), Icons.credit_card_rounded),
      AccountType.credit => (
          const Color(0xFF8B5CF6),
          Icons.credit_score_rounded
        ),
      AccountType.other => (const Color(0xFF64748B), Icons.savings_rounded),
    };
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      child: Icon(icon, size: size * 0.53, color: Colors.white),
    );
  }
}

/// 选择记账时间：快捷「今天 / 昨天 / 前天」+ 日期时间滚轮。
class _TimeSheet extends StatefulWidget {
  const _TimeSheet({required this.initial});

  final DateTime initial;

  @override
  State<_TimeSheet> createState() => _TimeSheetState();
}

class _TimeSheetState extends State<_TimeSheet> {
  late DateTime _value = widget.initial;

  /// 快捷按钮改了日期时，用新的 key 重建滚轮；滚轮自己滚动不改变它。
  int _wheelEpoch = 0;

  void _jumpTo(int daysAgo) {
    final now = DateTime.now();
    final day = now.subtract(Duration(days: daysAgo));
    setState(() {
      _value = DateTime(
        day.year,
        day.month,
        day.day,
        _value.hour,
        _value.minute,
      );
      _wheelEpoch++;
    });
  }

  @override
  Widget build(BuildContext context) {
    final palette = BeanPalette.of(context);
    final today = DateTime.now();
    final selectedDay = DateTime(_value.year, _value.month, _value.day);
    int daysAgoOf(DateTime d) =>
        DateTime(today.year, today.month, today.day).difference(d).inDays;

    return BeanSheet(
      title: '记账时间',
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              children: [
                for (var i = 0; i < 3; i++) ...[
                  if (i > 0) const SizedBox(width: 8),
                  _DayChip(
                    label: const ['今天', '昨天', '前天'][i],
                    selected: daysAgoOf(selectedDay) == i,
                    onTap: () => _jumpTo(i),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 4),
          SizedBox(
            height: 192,
            // Cupertino 滚轮默认跟随系统亮度；这里强制跟随 App 主题，暗色下才不会黑字黑底。
            // 文字样式走主题的 titleLarge，字体族才跟全局一致（不在组件里另起一套）。
            child: CupertinoTheme(
              data: CupertinoThemeData(
                brightness: Theme.of(context).brightness,
                textTheme: CupertinoTextThemeData(
                  dateTimePickerTextStyle:
                      Theme.of(context).textTheme.titleLarge?.copyWith(
                            fontSize: 19,
                            color: Theme.of(context).colorScheme.onSurface,
                          ),
                ),
              ),
              child: CupertinoDatePicker(
                key: ValueKey(_wheelEpoch),
                mode: CupertinoDatePickerMode.dateAndTime,
                initialDateTime: _value,
                use24hFormat: true,
                minuteInterval: 1,
                onDateTimeChanged: (value) => _value = value,
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
            child: _SurfaceKey(
              filled: true,
              onTap: () => Navigator.of(context).pop(_value),
              child: Text(
                '完成',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: _onAccentFill(context),
                ),
              ),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '选中的时间会显示在面板和明细里',
            style: TextStyle(fontSize: 12, color: palette.textSecondary),
          ),
        ],
      ),
    );
  }
}

class _DayChip extends StatelessWidget {
  const _DayChip({
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
    return Material(
      color: selected ? palette.neutral.raised : palette.neutral.sand,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onTap,
        child: Container(
          height: 36,
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: selected ? BeanColors.gold : Colors.transparent,
            ),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 13,
              fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
              color: selected ? BeanColors.goldDeep : palette.textSecondary,
            ),
          ),
        ),
      ),
    );
  }
}

/// 转账的「从 / 到」一行：整行可点，右侧显示当前账户。
class _TransferAccountChip extends StatelessWidget {
  const _TransferAccountChip({
    required this.label,
    required this.accountName,
    required this.onTap,
  });

  final String label;
  final String accountName;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = BeanPalette.of(context);
    return Material(
      color: palette.surface,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Container(
          height: 48,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: palette.neutral.lineStrong),
          ),
          child: Row(
            children: [
              Text(
                label,
                style: TextStyle(fontSize: 13, color: palette.textSecondary),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  accountName,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              Icon(
                Icons.expand_more_rounded,
                size: 18,
                color: palette.textSecondary,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
/// 备注弹窗：自己持有 TextEditingController（弹窗关闭动画期间还会重建），
/// 并给出「最近用过」的一键填充。
class _NoteDialog extends StatefulWidget {
  const _NoteDialog({required this.initial, required this.recentNotes});

  final String initial;
  final List<String> recentNotes;

  @override
  State<_NoteDialog> createState() => _NoteDialogState();
}

class _NoteDialogState extends State<_NoteDialog> {
  late final TextEditingController _controller =
      TextEditingController(text: widget.initial)
        ..selection = TextSelection.collapsed(offset: widget.initial.length);
  late String _draft = widget.initial;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _use(String note) {
    setState(() {
      _draft = note;
      _controller.text = note;
      _controller.selection =
          TextSelection.collapsed(offset: note.length);
    });
  }

  @override
  Widget build(BuildContext context) {
    final palette = BeanPalette.of(context);
    return AlertDialog(
      title: const Text(
        '备注',
        style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextFormField(
            controller: _controller,
            autofocus: true,
            maxLength: 40,
            maxLines: 2,
            minLines: 1,
            textInputAction: TextInputAction.done,
            decoration: const InputDecoration(
              hintText: '例如：和家人吃晚饭',
              counterText: '',
            ),
            onChanged: (value) => _draft = value,
            onFieldSubmitted: (value) => Navigator.of(context).pop(value),
          ),
          if (widget.recentNotes.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(
              '最近用过',
              style: TextStyle(fontSize: 12, color: palette.textSecondary),
            ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final note in widget.recentNotes)
                  GestureDetector(
                    onTap: () => _use(note),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: palette.neutral.sand,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        note,
                        style: const TextStyle(fontSize: 13),
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(_draft),
          child: const Text('确定'),
        ),
      ],
    );
  }
}
