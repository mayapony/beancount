import 'package:flutter/foundation.dart';

import '../db/enums.dart';

/// 搜索页的时间范围预设。边界按本地时间、半开区间计算。
enum SearchRange {
  thisMonth('本月'),
  lastThreeMonths('近三个月'),
  thisYear('今年'),
  all('全部');

  const SearchRange(this.label);

  final String label;
}

/// 一次搜索的全部条件。空值/空串表示该条件不限制。
@immutable
class LedgerFilter {
  const LedgerFilter({
    this.keyword = '',
    this.type,
    this.range = SearchRange.all,
    this.categoryId,
    this.accountId,
    this.tag,
    this.minCents,
    this.maxCents,
  });

  /// 匹配备注 / 分类名 / 账户名 / 标签名（大小写不敏感）。
  final String keyword;

  /// null = 收支不限。
  final EntryType? type;

  final SearchRange range;

  /// 选中一级分类时，检索会包含它的二级分类。
  final String? categoryId;
  final String? accountId;
  final String? tag;
  final int? minCents;
  final int? maxCents;

  bool get hasKeyword => keyword.trim().isNotEmpty;

  /// 是否设置了任何条件（「清空筛选」按钮的可用状态）。
  bool get isNarrowed =>
      hasKeyword ||
      type != null ||
      range != SearchRange.all ||
      categoryId != null ||
      accountId != null ||
      tag != null ||
      minCents != null ||
      maxCents != null;

  /// 只清结构化条件，保留关键词（与 spec 一致）。
  LedgerFilter clearingFilters() => LedgerFilter(keyword: keyword);

  /// 时间区间（半开）：`from` 包含，`to` 不包含；null 表示不限。
  ({DateTime? from, DateTime? to}) bounds(DateTime now) {
    switch (range) {
      case SearchRange.all:
        return (from: null, to: null);
      case SearchRange.thisMonth:
        return (
          from: DateTime(now.year, now.month),
          to: DateTime(now.year, now.month + 1),
        );
      case SearchRange.lastThreeMonths:
        return (
          from: DateTime(now.year, now.month - 2),
          to: DateTime(now.year, now.month + 1),
        );
      case SearchRange.thisYear:
        return (from: DateTime(now.year), to: DateTime(now.year + 1));
    }
  }

  @override
  bool operator ==(Object other) =>
      other is LedgerFilter &&
      other.keyword == keyword &&
      other.type == type &&
      other.range == range &&
      other.categoryId == categoryId &&
      other.accountId == accountId &&
      other.tag == tag &&
      other.minCents == minCents &&
      other.maxCents == maxCents;

  @override
  int get hashCode => Object.hash(
        keyword,
        type,
        range,
        categoryId,
        accountId,
        tag,
        minCents,
        maxCents,
      );
}
