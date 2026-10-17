import 'package:drift/drift.dart';

import '../../theme/tokens.dart';
import '../../utils/colors.dart';
import '../db/app_database.dart';
import '../db/enums.dart';

/// 分类被交易或子分类占用时抛出，调用方据此提供"迁移"或"取消"。
class CategoryInUseException implements Exception {
  CategoryInUseException(this.categoryId, this.reason);

  final String categoryId;

  /// 人类可读的原因，直接展示在 SnackBar / 对话框里。
  final String reason;

  @override
  String toString() => 'CategoryInUseException($categoryId): $reason';
}

/// 分类仓储：唯一负责分类树的读写与约束（最多两级、被引用不可删）。
///
/// 领域模型直接用 drift 生成的 `Category`（表 `categories` 的行），
/// 不再单独造一层 DTO——查询结果就是页面要用的东西，少一次映射。
class CategoryRepository {
  CategoryRepository(this._db);

  final AppDatabase _db;

  /// 某类型下的全部分类，一级在前、按 `sortOrder` 排。
  Future<List<Category>> all(CategoryType type) async {
    final query = _db.select(_db.categories)
      ..where((t) => t.type.equalsValue(type))
      ..orderBy([
        (t) => OrderingTerm(expression: t.sortOrder),
        (t) => OrderingTerm(expression: t.name),
      ]);
    return query.get();
  }

  /// 全部分类（两级都在内），按类型与排序号排好——记账面板一次取走。
  Future<List<Category>> allCategories() async {
    final query = _db.select(_db.categories)
      ..orderBy([
        (t) => OrderingTerm(expression: t.type),
        (t) => OrderingTerm(expression: t.sortOrder),
        (t) => OrderingTerm(expression: t.name),
      ]);
    return query.get();
  }

  /// 一级分类（`parentId` 为空）。
  Future<List<Category>> roots(CategoryType type) async {
    final query = _db.select(_db.categories)
      ..where((t) => t.type.equalsValue(type) & t.parentId.isNull())
      ..orderBy([
        (t) => OrderingTerm(expression: t.sortOrder),
        (t) => OrderingTerm(expression: t.name),
      ]);
    return query.get();
  }

  Future<List<Category>> childrenOf(String parentId) async {
    final query = _db.select(_db.categories)
      ..where((t) => t.parentId.equals(parentId))
      ..orderBy([(t) => OrderingTerm(expression: t.sortOrder)]);
    return query.get();
  }

  Future<Category?> byId(String id) {
    return (_db.select(_db.categories)..where((t) => t.id.equals(id)))
        .getSingleOrNull();
  }

  /// 按「名称 + 类型 + 父级」精确查重（导入时复用同一分类）。
  Future<Category?> findByName(
    String name,
    CategoryType type, {
    String? parentId,
  }) {
    final query = _db.select(_db.categories)
      ..where(
        (t) =>
            t.name.equals(name) &
            t.type.equalsValue(type) &
            (parentId == null ? t.parentId.isNull() : t.parentId.equals(parentId)),
      );
    return query.getSingleOrNull();
  }

  /// 保证分类存在：有则复用，无则按名称分配颜色/图标后新建。
  ///
  /// 导入流程靠它做到"50 行同一个分类只建 1 条"。
  Future<Category> ensure({
    required String name,
    required CategoryType type,
    String? parentId,
  }) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) {
      throw ArgumentError.value(name, 'name', '分类名不能为空');
    }
    if (parentId != null) {
      final parent = await byId(parentId);
      if (parent == null) {
        throw ArgumentError.value(parentId, 'parentId', '父分类不存在');
      }
      if (parent.parentId != null) {
        throw StateError('最多两级分类：「${parent.name}」已是二级分类');
      }
      if (parent.type != type) {
        throw ArgumentError('子分类类型必须与父分类一致');
      }
    }

    final existing = await findByName(trimmed, type, parentId: parentId);
    if (existing != null) return existing;

    final order = await _nextSortOrder(type);
    final id = 'cat-${DateTime.now().microsecondsSinceEpoch}-$order';
    await _db.into(_db.categories).insert(
          CategoriesCompanion.insert(
            id: id,
            name: trimmed,
            type: type,
            parentId: Value(parentId),
            color: _colorFor(trimmed, type),
            icon: iconForCategoryName(trimmed),
            sortOrder: Value(order),
          ),
        );
    return (await byId(id))!;
  }

  Future<Category> create({
    required String name,
    required CategoryType type,
    String? parentId,
    int? color,
    String? icon,
  }) async {
    final category = await ensure(name: name, type: type, parentId: parentId);
    if (color != null || icon != null) {
      await (_db.update(_db.categories)..where((t) => t.id.equals(category.id)))
          .write(
        CategoriesCompanion(
          color: color == null ? const Value.absent() : Value(color),
          icon: icon == null ? const Value.absent() : Value(icon),
        ),
      );
      return (await byId(category.id))!;
    }
    return category;
  }

  Future<void> rename(String id, String name) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) throw ArgumentError.value(name, 'name', '分类名不能为空');
    await (_db.update(_db.categories)..where((t) => t.id.equals(id))).write(
      CategoriesCompanion(name: Value(trimmed)),
    );
  }

  /// 删除分类。
  ///
  /// - 被交易引用 → 拒绝（抛 [CategoryInUseException]）；
  /// - 有子分类 → 子分类也没被引用时一并删除，否则同样拒绝；
  /// - 否则删除。
  Future<void> delete(String id) async {
    final used = await transactionCount(id);
    if (used > 0) {
      throw CategoryInUseException(id, '该分类下已有 $used 笔交易');
    }

    final children = await childrenOf(id);
    for (final child in children) {
      final childUsed = await transactionCount(child.id);
      if (childUsed > 0) {
        throw CategoryInUseException(id, '「${child.name}」下已有 $childUsed 笔交易');
      }
    }

    await _db.transaction(() async {
      for (final child in children) {
        await (_db.delete(_db.categories)..where((t) => t.id.equals(child.id)))
            .go();
      }
      await (_db.delete(_db.categories)..where((t) => t.id.equals(id))).go();
    });
  }

  Future<int> transactionCount(String categoryId) async {
    final row = await _db.customSelect(
      'SELECT COUNT(*) AS c FROM transactions WHERE category_id = ?',
      variables: [Variable.withString(categoryId)],
    ).getSingle();
    return row.read<int>('c');
  }

  Future<int> _nextSortOrder(CategoryType type) async {
    final maxOrder = _db.categories.sortOrder.max();
    final query = _db.selectOnly(_db.categories)
      ..addColumns([maxOrder])
      ..where(_db.categories.type.equalsValue(type));
    final row = await query.getSingle();
    return (row.read(maxOrder) ?? -1) + 1;
  }

  /// 新分类的配色：按名称散列到对应类型的色板，保证同名同类永远同色。
  int _colorFor(String name, CategoryType type) {
    final palette = type == CategoryType.income
        ? _incomePalette
        : _expensePalette;
    return palette[name.hashCode.abs() % palette.length];
  }

  /// 导入的分类没有图标，按名字猜一个；猜不到就用「其他」。
  static String iconForCategoryName(String name) => _iconByName[name] ??
      (name.contains('餐') || name.contains('饭') || name.contains('食')
          ? 'restaurant'
          : name.contains('车') || name.contains('交通')
              ? 'directions_bus'
              : name.contains('医') || name.contains('药')
                  ? 'medication'
                  : name.contains('学') || name.contains('课')
                      ? 'school'
                      : 'more_horiz');

  static const _iconByName = <String, String>{
    '外卖': 'delivery_dining',
    '零食': 'cookie',
    '饮料': 'local_cafe',
    '服装': 'checkroom',
    '快递': 'local_shipping',
    '烟酒': 'wine_bar',
    '游戏': 'sports_esports',
    '打车': 'local_taxi',
    '日用品': 'cleaning_services',
    '工作': 'work',
    '工资': 'payments',
    '奖金': 'redeem',
    '兼职': 'work',
    '理财': 'trending_up',
    '红包': 'card_giftcard',
    '居家': 'home',
    '数码': 'devices',
    '宠物': 'pets',
    '旅行': 'flight',
    '运动': 'fitness_center',
    '教育': 'school',
  };

  static final List<int> _expensePalette = [
    for (final c in BeanColors.categories) argbOf(c),
  ];

  static final List<int> _incomePalette = [
    for (final c in BeanColors.incomeCategories) argbOf(c),
  ];
}
