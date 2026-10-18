import '../../data/db/app_database.dart';
import '../../data/db/enums.dart';

/// 识别结果落到「分类 / 标签 / 账户」时的匹配规则。
///
/// 全部是纯函数 + 常量表：没有数据库、没有网络，识别链路和单测共用同一份词表。
/// 账户只做名称/别名的相等与包含匹配，MUST NOT 做编辑距离之类的模糊猜测——
/// 猜错账户会让余额记到别人头上。

/// 名称归一化：全角转半角、去空白与标点、ASCII 转小写；只保留中文与字母数字。
///
/// 例：`" 交 通 "`、`"ＡＢＣ"`、`"咖啡（店）"` → `"交通"`、`"abc"`、`"咖啡店"`。
String normalizeName(String? raw) {
  if (raw == null || raw.isEmpty) return '';
  final out = StringBuffer();
  for (var rune in raw.runes) {
    if (rune == 0x3000) continue; // 全角空格
    if (rune >= 0xFF01 && rune <= 0xFF5E) rune -= 0xFEE0; // 全角 ASCII → 半角
    if (_isHan(rune)) {
      out.writeCharCode(rune);
      continue;
    }
    if (rune >= 0x30 && rune <= 0x39) {
      out.writeCharCode(rune); // 0-9
    } else if (rune >= 0x61 && rune <= 0x7A) {
      out.writeCharCode(rune); // a-z
    } else if (rune >= 0x41 && rune <= 0x5A) {
      out.writeCharCode(rune + 0x20); // A-Z → a-z
    }
  }
  return out.toString();
}

bool _isHan(int rune) =>
    (rune >= 0x4E00 && rune <= 0x9FFF) || (rune >= 0x3400 && rune <= 0x4DBF);

/// 解析用的分类关键字表：规范分类名 → 命中词。顺序有意义：更具体的放前面。
const kCategoryKeywords = <String, List<String>>{
  '餐饮': [
    '餐厅', '饭馆', '饭店', '面馆', '小吃', '烧烤', '火锅', '食堂', '咖啡',
    '奶茶', '茶饮', '快餐', '牛肉面', '米线', '饺子', '面', '餐', '食',
  ],
  '交通': ['打车', '滴滴', '出租车', '地铁', '公交', '高铁', '加油', '停车', '机票'],
  '购物': ['超市', '便利店', '商场', '百货', '超市发', '药妆', '网购'],
  '医疗': ['药房', '药店', '医院', '诊所', '体检'],
  '娱乐': ['电影', '影城', 'ktv', '游戏', '演出'],
  '旅行': ['酒店', '民宿', '旅行', '景区', '门票'],
};

/// 分类别名：规范名 → 用户可能用过的同类名字（改名后仍能命中）。
const kCategoryAliases = <String, List<String>>{
  '餐饮': ['吃饭', '吃喝', '伙食'],
  '交通': ['出行', '打的'],
  '购物': ['买东西', '购物中心'],
  '医疗': ['看病', '买药'],
  '娱乐': ['看电影', '玩乐'],
  '旅行': ['旅游', '住宿'],
};

/// 标签词表：标签名 → 命中词。名称固定，避免把商家名变成标签。
const kTagKeywords = <String, List<String>>{
  '微信支付': ['微信支付', '微信'],
  '支付宝': ['支付宝'],
  '云闪付': ['云闪付', '银联'],
  '现金': ['现金'],
  '咖啡': ['咖啡', '拿铁', '美式'],
  '奶茶': ['奶茶', '茶饮'],
  '外卖': ['外卖'],
  '打车': ['打车', '滴滴', '网约车'],
  '超市': ['超市', '便利店'],
  '早餐': ['早餐'],
  '午餐': ['午餐', '午饭'],
  '晚餐': ['晚餐', '晚饭'],
};

/// 账户别名分组：同组内任一关键词出现在账户名与文本里，就算命中。
const kAccountAliasGroups = <List<String>>[
  ['微信', '零钱', '微信支付'],
  ['支付宝', '花呗', '余额宝'],
  ['云闪付', '银联'],
  ['银行卡', '储蓄卡', '借记卡', '信用卡'],
];

/// 把识别出的分类名解析成规范名（别名 → 规范名）；认不出时原样返回归一化结果。
String? canonicalCategoryName(String? name) {
  final normalized = normalizeName(name);
  if (normalized.isEmpty) return null;
  for (final entry in kCategoryAliases.entries) {
    if (entry.value.any((alias) => normalizeName(alias) == normalized)) {
      return entry.key;
    }
  }
  return normalized;
}

/// 在已有分类里找识别结果对应的那一个；找不到返回 null（由调用方决定是否新建）。
Category? matchCategory(
  String? guessName,
  Iterable<Category> categories,
  CategoryType type,
) {
  final canonical = canonicalCategoryName(guessName);
  if (canonical == null) return null;
  final wanted = <String>{
    normalizeName(guessName),
    canonical,
    ...?kCategoryAliases[canonical]?.map(normalizeName),
  };
  for (final category in categories) {
    if (category.type != type) continue;
    if (wanted.contains(normalizeName(category.name))) return category;
  }
  return null;
}

/// 从识别文本生成标签候选：已有标签优先复用，其次按词表补充，最多 [limit] 个。
List<String> tagCandidates(
  String? text, {
  Iterable<String> existingNames = const [],
  int limit = 2,
}) {
  if (limit <= 0) return const [];
  final haystack = normalizeName(text);
  if (haystack.isEmpty) return const [];

  final existingByKey = <String, String>{};
  for (final name in existingNames) {
    final key = normalizeName(name);
    if (key.isNotEmpty) existingByKey.putIfAbsent(key, () => name);
  }

  final reused = <String>[];
  final fresh = <String>[];
  final seen = <String>{};
  for (final entry in kTagKeywords.entries) {
    final key = normalizeName(entry.key);
    final hit = entry.value.any((word) => haystack.contains(normalizeName(word)));
    if (!hit || !seen.add(key)) continue;
    if (existingByKey.containsKey(key)) {
      reused.add(existingByKey[key]!);
    } else {
      fresh.add(entry.key);
    }
  }
  return [...reused, ...fresh].take(limit).toList(growable: false);
}

/// 从识别文本里匹配已有账户；匹配不到返回 null（调用方沿用上次账户）。
///
/// 规则：账户名归一化后是文本的子串，或账户名与文本命中同一组支付别名。
/// 命中多个时取名称最长的那个，避免「微信」抢走「微信零钱」。
Account? matchAccount(String? text, Iterable<Account> accounts) {
  final haystack = normalizeName(text);
  if (haystack.isEmpty) return null;

  Account? best;
  var bestLength = 0;
  for (final account in accounts) {
    final name = normalizeName(account.name);
    if (name.isEmpty) continue;
    final byName = name.length >= 2 && haystack.contains(name);
    final byAlias = _aliasHit(name, haystack);
    if (!byName && !byAlias) continue;
    if (name.length > bestLength) {
      best = account;
      bestLength = name.length;
    }
  }
  return best;
}

bool _aliasHit(String accountName, String haystack) {
  for (final group in kAccountAliasGroups) {
    final inAccount = group.any((word) => accountName.contains(normalizeName(word)));
    if (!inAccount) continue;
    if (group.any((word) => haystack.contains(normalizeName(word)))) return true;
  }
  return false;
}
