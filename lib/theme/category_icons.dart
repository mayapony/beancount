import 'package:flutter/material.dart';

/// 分类图标的**唯一真相**：数据库 `categories.icon` 存的是这里的 key，
/// UI 靠 [categoryIconFor] 把 key 还原成图标。
///
/// 支出 12 个的顺序与 `BeanColors.categoryNames` / `BeanColors.categories` 一一对应，
/// 旧的"按下标取图标"代码依赖这个顺序，不要重排。
const kExpenseCategoryIconKeys = <String>[
  'restaurant',
  'directions_bus',
  'shopping_bag',
  'movie',
  'home',
  'local_hospital',
  'school',
  'flight',
  'fitness_center',
  'devices',
  'pets',
  'more_horiz',
];

/// 收入分类的图标（工资 / 奖金 / 兼职 / 理财 / 红包 / 其他收入）。
const kIncomeCategoryIconKeys = <String>[
  'payments',
  'redeem',
  'work',
  'trending_up',
  'card_giftcard',
  'savings',
];

const kCategoryIconByKey = <String, IconData>{
  // 支出
  'restaurant': Icons.restaurant_rounded,
  'directions_bus': Icons.directions_bus_rounded,
  'shopping_bag': Icons.shopping_bag_rounded,
  'movie': Icons.movie_rounded,
  'home': Icons.home_rounded,
  'local_hospital': Icons.local_hospital_rounded,
  'school': Icons.school_rounded,
  'flight': Icons.flight_rounded,
  'fitness_center': Icons.fitness_center_rounded,
  'devices': Icons.devices_rounded,
  'pets': Icons.pets_rounded,
  'more_horiz': Icons.more_horiz_rounded,
  // 收入
  'payments': Icons.payments_rounded,
  'redeem': Icons.redeem_rounded,
  'work': Icons.work_rounded,
  'trending_up': Icons.trending_up_rounded,
  'card_giftcard': Icons.card_giftcard_rounded,
  'savings': Icons.savings_rounded,
  // 导入时按名字猜到的图标（BeeCount 的分类名很具体）
  'delivery_dining': Icons.delivery_dining_rounded,
  'cookie': Icons.cookie_rounded,
  'local_cafe': Icons.local_cafe_rounded,
  'checkroom': Icons.checkroom_rounded,
  'local_shipping': Icons.local_shipping_rounded,
  'wine_bar': Icons.wine_bar_rounded,
  'sports_esports': Icons.sports_esports_rounded,
  'local_taxi': Icons.local_taxi_rounded,
  'cleaning_services': Icons.cleaning_services_rounded,
  'medication': Icons.medication_rounded,
};

/// 未知 key 一律退回「其他」，保证新增分类不会因为图标名写错而崩。
IconData categoryIconFor(String key) =>
    kCategoryIconByKey[key] ?? Icons.more_horiz_rounded;

/// 兼容：旧的"按下标取图标"。
List<IconData> get kCategoryIcons => [
      for (final key in kExpenseCategoryIconKeys) categoryIconFor(key),
    ];
