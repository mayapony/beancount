import 'db/app_database.dart';
import 'db/enums.dart';

/// 一个分类候选：一级名 + 它的二级名。
///
/// 提示词里渲染成 `出行交通（打车、停车费）/ 食品餐饮`，模型选二级时也知道它
/// 属于哪个一级，不会把「打车」当成一级分类。
class CategoryChoice {
  const CategoryChoice(this.name, [this.children = const []]);

  final String name;
  final List<String> children;

  String toPrompt() =>
      children.isEmpty ? name : '$name（${children.join('、')}）';
}

/// 分类库里的一条建议分类。
///
/// 只是**建议**：用户在面板里点中哪一条，才会真的写进账本。库本身不落库，
/// 也不随版本升级偷偷往用户账本里塞分类。
class LibraryCategory {
  const LibraryCategory({
    required this.name,
    required this.iconKey,
    this.type = CategoryType.expense,
    this.aliases = const [],
    this.children = const [],
  });

  final String name;
  final String iconKey;
  final CategoryType type;

  /// 搜索用的别名：输入「打车」「taxi」都能找到「出行交通 / 打车」。
  final List<String> aliases;

  final List<LibraryCategory> children;

  bool matches(String query) {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return true;
    if (name.toLowerCase().contains(q)) return true;
    return aliases.any((alias) => alias.toLowerCase().contains(q));
  }
}

/// 内置分类库：常见的一级分类 + 具体到能直接用的二级分类。
///
/// 设计取舍：
/// - 只收「大概率用得上」的，不做穷举——库太杂反而难找；
/// - 二级分类必须挂在有意义的一级下面，避免出现孤立的「打车」；
/// - 图标全走 Material，不引图片素材。
const kCategoryLibrary = <LibraryCategory>[
  LibraryCategory(
    name: '食品餐饮',
    iconKey: 'restaurant',
    aliases: ['吃饭', '餐饮', '外卖', 'food'],
    children: [
      LibraryCategory(name: '早餐', iconKey: 'free_breakfast', aliases: ['早饭']),
      LibraryCategory(name: '午餐', iconKey: 'lunch_dining', aliases: ['午饭']),
      LibraryCategory(name: '晚餐', iconKey: 'dinner_dining', aliases: ['晚饭']),
      LibraryCategory(name: '外卖', iconKey: 'delivery_dining', aliases: ['美团', '饿了么']),
      LibraryCategory(name: '咖啡奶茶', iconKey: 'local_cafe', aliases: ['咖啡', '奶茶', '瑞幸', '星巴克']),
      LibraryCategory(name: '零食', iconKey: 'cookie', aliases: ['小吃']),
      LibraryCategory(name: '买菜', iconKey: 'local_grocery_store', aliases: ['超市', '生鲜']),
    ],
  ),
  LibraryCategory(
    name: '出行交通',
    iconKey: 'directions_bus',
    aliases: ['交通', '出行'],
    children: [
      LibraryCategory(name: '打车', iconKey: 'local_taxi', aliases: ['滴滴', '出租车', '网约车']),
      LibraryCategory(name: '公共交通', iconKey: 'directions_subway', aliases: ['地铁', '公交']),
      LibraryCategory(name: '停车费', iconKey: 'local_parking', aliases: ['停车']),
      LibraryCategory(name: '加油', iconKey: 'local_gas_station', aliases: ['油费']),
      LibraryCategory(name: '火车', iconKey: 'train', aliases: ['高铁', '动车']),
      LibraryCategory(name: '飞机', iconKey: 'flight', aliases: ['机票']),
      LibraryCategory(name: '保养修车', iconKey: 'car_repair', aliases: ['保养', '维修']),
    ],
  ),
  LibraryCategory(
    name: '购物消费',
    iconKey: 'shopping_bag',
    aliases: ['购物', '买东西'],
    children: [
      LibraryCategory(name: '日用百货', iconKey: 'shopping_cart', aliases: ['日用品', '超市']),
      LibraryCategory(name: '服饰鞋包', iconKey: 'checkroom', aliases: ['衣服', '鞋']),
      LibraryCategory(name: '数码电器', iconKey: 'devices', aliases: ['数码', '电子产品']),
      LibraryCategory(name: '美妆护肤', iconKey: 'spa', aliases: ['护肤', '化妆品']),
      LibraryCategory(name: '母婴', iconKey: 'child_care', aliases: ['宝宝', '奶粉']),
    ],
  ),
  LibraryCategory(
    name: '居家生活',
    iconKey: 'home',
    aliases: ['居家', '家用'],
    children: [
      LibraryCategory(name: '房租', iconKey: 'home_work', aliases: ['租金']),
      LibraryCategory(name: '水电燃气', iconKey: 'bolt', aliases: ['电费', '水费', '燃气费']),
      LibraryCategory(name: '物业', iconKey: 'apartment', aliases: ['物业费']),
      LibraryCategory(name: '家政保洁', iconKey: 'cleaning_services', aliases: ['保洁', '打扫']),
    ],
  ),
  LibraryCategory(
    name: '休闲娱乐',
    iconKey: 'movie',
    aliases: ['娱乐'],
    children: [
      LibraryCategory(name: '电影演出', iconKey: 'movie', aliases: ['电影', '演出', '话剧']),
      LibraryCategory(name: '游戏', iconKey: 'sports_esports', aliases: ['充值']),
      LibraryCategory(name: '酒吧夜店', iconKey: 'wine_bar', aliases: ['酒吧']),
      LibraryCategory(name: '会员订阅', iconKey: 'subscriptions', aliases: ['会员', '订阅']),
    ],
  ),
  LibraryCategory(
    name: '健康医疗',
    iconKey: 'local_hospital',
    aliases: ['医疗', '看病'],
    children: [
      LibraryCategory(name: '门诊挂号', iconKey: 'medical_services', aliases: ['挂号', '门诊']),
      LibraryCategory(name: '药品', iconKey: 'local_pharmacy', aliases: ['买药', '药']),
      LibraryCategory(name: '体检', iconKey: 'monitor_heart', aliases: ['检查']),
      LibraryCategory(name: '健身运动', iconKey: 'fitness_center', aliases: ['健身', '运动', '健身房']),
    ],
  ),
  LibraryCategory(
    name: '文化教育',
    iconKey: 'school',
    aliases: ['教育', '学习'],
    children: [
      LibraryCategory(name: '书籍', iconKey: 'menu_book', aliases: ['买书', '书']),
      LibraryCategory(name: '课程培训', iconKey: 'cast_for_education', aliases: ['课程', '培训', '学费']),
      LibraryCategory(name: '考试报名', iconKey: 'assignment', aliases: ['考试']),
    ],
  ),
  LibraryCategory(
    name: '送礼人情',
    iconKey: 'card_giftcard',
    aliases: ['人情', '礼'],
    children: [
      LibraryCategory(name: '红包', iconKey: 'redeem', aliases: ['压岁钱']),
      LibraryCategory(name: '礼物', iconKey: 'card_giftcard', aliases: ['送礼']),
      LibraryCategory(name: '礼金', iconKey: 'volunteer_activism', aliases: ['份子钱', '随礼']),
    ],
  ),
  LibraryCategory(
    name: '通讯网络',
    iconKey: 'phone_iphone',
    aliases: ['通信'],
    children: [
      LibraryCategory(name: '话费', iconKey: 'phone_iphone', aliases: ['手机费']),
      LibraryCategory(name: '宽带', iconKey: 'router', aliases: ['网费']),
      LibraryCategory(name: '软件订阅', iconKey: 'subscriptions', aliases: ['AI', '会员', '订阅']),
    ],
  ),
  LibraryCategory(
    name: '宠物',
    iconKey: 'pets',
    children: [
      LibraryCategory(name: '宠物食品', iconKey: 'pets', aliases: ['猫粮', '狗粮']),
      LibraryCategory(name: '宠物医疗', iconKey: 'medical_services', aliases: ['疫苗', '看病']),
      LibraryCategory(name: '宠物美容', iconKey: 'content_cut', aliases: ['洗澡']),
    ],
  ),
  LibraryCategory(
    name: '旅行',
    iconKey: 'flight',
    aliases: ['旅游'],
    children: [
      LibraryCategory(name: '酒店', iconKey: 'hotel', aliases: ['住宿', '民宿']),
      LibraryCategory(name: '门票', iconKey: 'local_activity', aliases: ['景区']),
      LibraryCategory(name: '旅行团', iconKey: 'luggage', aliases: ['跟团']),
    ],
  ),
  LibraryCategory(
    name: '其他',
    iconKey: 'more_horiz',
  ),
  LibraryCategory(
    name: '工资',
    iconKey: 'payments',
    type: CategoryType.income,
    aliases: ['薪水'],
  ),
  LibraryCategory(
    name: '奖金',
    iconKey: 'redeem',
    type: CategoryType.income,
  ),
  LibraryCategory(
    name: '兼职',
    iconKey: 'work',
    type: CategoryType.income,
    aliases: ['副业'],
  ),
  LibraryCategory(
    name: '理财收益',
    iconKey: 'trending_up',
    type: CategoryType.income,
    aliases: ['利息', '分红', '基金'],
  ),
  LibraryCategory(
    name: '报销',
    iconKey: 'receipts',
    type: CategoryType.income,
  ),
  LibraryCategory(
    name: '其他收入',
    iconKey: 'savings',
    type: CategoryType.income,
  ),
];

/// 展平成「一级 + 它下面每个二级」的可搜索条目，供选择器列表使用。
class LibraryEntry {
  const LibraryEntry({
    required this.category,
    this.parent,
  });

  final LibraryCategory category;

  /// 二级分类才有父级。
  final LibraryCategory? parent;

  String get displayPath =>
      parent == null ? category.name : '${parent!.name} / ${category.name}';
}

List<LibraryEntry> flattenCategoryLibrary({CategoryType? type}) {
  final out = <LibraryEntry>[];
  for (final root in kCategoryLibrary) {
    if (type != null && root.type != type) continue;
    out.add(LibraryEntry(category: root));
    for (final child in root.children) {
      out.add(LibraryEntry(category: child, parent: root));
    }
  }
  return out;
}

/// 按关键词过滤库；父级命中时，它的二级也一起留下（方便「输入交通找打车」）。
List<LibraryEntry> searchCategoryLibrary(String query, {CategoryType? type}) {
  final q = query.trim();
  if (q.isEmpty) return flattenCategoryLibrary(type: type);

  final out = <LibraryEntry>[];
  for (final root in kCategoryLibrary) {
    if (type != null && root.type != type) continue;
    final rootHit = root.matches(q);
    if (rootHit) {
      out.add(LibraryEntry(category: root));
      for (final child in root.children) {
        out.add(LibraryEntry(category: child, parent: root));
      }
      continue;
    }
    for (final child in root.children) {
      if (child.matches(q)) {
        out.add(LibraryEntry(category: child, parent: root));
      }
    }
  }
  return out;
}
/// 把账本里的真实分类树转成识别提示词用的候选（一级 + 二级名）。
///
/// 识别器只认这个入口：提示词里的分类 MUST 来自用户账本，而不是内置列表。
List<CategoryChoice> categoryChoicesFrom(
  Iterable<Category> categories,
  CategoryType type,
) {
  final all = categories.toList();
  return [
    for (final root in all)
      if (root.parentId == null && root.type == type)
        CategoryChoice(
          root.name,
          [
            for (final child in all)
              if (child.parentId == root.id) child.name,
          ],
        ),
  ];
}
/// 反向匹配：在一段文本里找分类库里出现过的名字或别名。
///
/// 用于「通知/无障碍拿到的文本里带商户名」的场景——这里的方向是
/// 「文本包含分类名」，和 [searchCategoryLibrary]（查询词包含于分类名）相反。
/// 命中的按词长从长到短排序，长词更具体（「叮咚买菜」优于「买菜」）。
List<LibraryEntry> libraryEntriesInText(
  String text, {
  CategoryType? type,
}) {
  if (text.trim().isEmpty) return const [];
  final hits = <(int, LibraryEntry)>[];
  for (final entry in flattenCategoryLibrary(type: type)) {
    final keys = [entry.category.name, ...entry.category.aliases];
    for (final key in keys) {
      if (key.length >= 2 && text.contains(key)) {
        hits.add((key.length, entry));
        break;
      }
    }
  }
  hits.sort((a, b) => b.$1.compareTo(a.$1));
  return [for (final hit in hits) hit.$2];
}