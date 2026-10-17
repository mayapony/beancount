import '../../data/db/app_database.dart';
import '../../data/db/enums.dart';
import '../../data/dedupe.dart';
import 'import_models.dart';

/// 本地已有数据：用来判断"哪些分类/账户/标签是新的"和"哪些行重复了"。
class ExistingLedger {
  const ExistingLedger({
    this.categories = const [],
    this.accounts = const [],
    this.tagNames = const {},
    this.dedupeKeys = const {},
  });

  final List<Category> categories;
  final List<Account> accounts;
  final Set<String> tagNames;
  final Set<String> dedupeKeys;
}

/// 计划中要新建的分类（父分类排在子分类前面）。
class PendingCategory {
  const PendingCategory({
    required this.name,
    required this.type,
    this.parentName,
  });

  final String name;
  final CategoryType type;
  final String? parentName;

  String get display => parentName == null ? name : '$parentName / $name';
}

/// 计划中的一笔交易。只带解析结果和去重键——分类/账户 id 在写入时
/// 按名字统一解析，避免"预览时算了一套 id、写入时又算一套"。
class PlannedEntry {
  const PlannedEntry({required this.row, required this.dedupeKey});

  final ParsedRow row;
  final String dedupeKey;
}

/// 预览与写入共用同一份计划：预览看到的数字就是实际会发生的。
class ImportPlan {
  const ImportPlan({
    required this.entries,
    required this.skipped,
    required this.newCategories,
    required this.newAccounts,
    required this.newTags,
    required this.attachmentFiles,
    required this.attachmentBytes,
    this.attachmentWarnings = const [],
    this.totalRows = 0,
  });

  final List<PlannedEntry> entries;
  final List<SkippedRow> skipped;
  final List<PendingCategory> newCategories;
  final List<String> newAccounts;
  final List<String> newTags;

  /// 会随交易落盘的附件文件名（去重后的张数）。
  final List<String> attachmentFiles;
  final int attachmentBytes;
  final List<String> attachmentWarnings;
  final int totalRows;

  int get importable => entries.length;
  int get skippedCount => skipped.length;

  Map<String, int> get skipReasons {
    final map = <String, int>{};
    for (final item in skipped) {
      map.update(item.reason, (v) => v + 1, ifAbsent: () => 1);
    }
    return map;
  }

  bool get isEmpty => entries.isEmpty;

  /// 附件体积（MB，保留一位小数），预览里展示。
  String get attachmentSizeLabel =>
      '${(attachmentBytes / 1024 / 1024).toStringAsFixed(1)} MB';
}

/// 把解析结果对成本地数据能直接执行的计划（纯函数，方便单测）。
///
/// [availableAttachments] 是包里真实存在的文件 → 字节数，用来算体积与缺图。
ImportPlan buildImportPlan({
  required ParseResult parsed,
  required ExistingLedger existing,
  required Map<String, int> availableAttachments,
}) {
  final skipped = <SkippedRow>[...parsed.skipped];

  final categoryKeys = <String>{
    for (final c in existing.categories)
      if (c.parentId == null) '${c.type.name}/${c.name}',
  };
  final childKeys = <String>{
    for (final c in existing.categories)
      if (c.parentId != null) '${c.parentId}/${c.name}',
  };
  final parentKeysByName = <String, String>{
    for (final c in existing.categories)
      if (c.parentId == null) '${c.type.name}/${c.name}': c.id,
  };
  final accountNames = {for (final a in existing.accounts) a.name};
  final tagNames = {...existing.tagNames};
  final dedupeKeys = {...existing.dedupeKeys};

  final newCategories = <PendingCategory>[];
  final newAccounts = <String>[];
  final newTags = <String>[];
  final entries = <PlannedEntry>[];
  final attachmentWarnings = <String>[];
  final usedAttachments = <String>{};

  void addCategory(PendingCategory pending) {
    final exists = pending.parentName == null
        ? categoryKeys.contains('${pending.type.name}/${pending.name}')
        : (parentKeysByName['${pending.type.name}/${pending.parentName}'] != null &&
            childKeys.contains(
              '${parentKeysByName['${pending.type.name}/${pending.parentName}']}/${pending.name}',
            ));
    if (exists) return;
    final duplicate = newCategories.any((p) =>
        p.name == pending.name &&
        p.type == pending.type &&
        p.parentName == pending.parentName);
    if (duplicate) return;
    newCategories.add(pending);
  }

  for (final row in parsed.rows) {
    final type = row.type;
    final key = dedupeKeyFor(
      happenedAt: row.happenedAt,
      amountCents: row.amountCents,
      note: row.note,
    );
    if (dedupeKeys.contains(key)) {
      skipped.add(SkippedRow(
        lineNumber: row.lineNumber,
        reason: '已存在（同一时间、金额、备注）',
        summary: row.note,
      ));
      continue;
    }
    dedupeKeys.add(key);

    final categoryType =
        type == EntryType.income ? CategoryType.income : CategoryType.expense;

    if (row.subcategoryName.isEmpty) {
      addCategory(PendingCategory(name: row.categoryName, type: categoryType));
    } else {
      addCategory(
        PendingCategory(
          name: row.subcategoryName,
          type: categoryType,
          parentName: row.categoryName,
        ),
      );
    }

    final accountName = row.accountName.trim();
    if (accountName.isNotEmpty &&
        !accountNames.contains(accountName) &&
        !newAccounts.contains(accountName)) {
      newAccounts.add(accountName);
    }

    for (final tag in row.tags) {
      if (!tagNames.contains(tag) && !newTags.contains(tag)) {
        newTags.add(tag);
      }
    }

    for (final name in row.attachments) {
      if (name.contains('/') || name.contains('\\') || name.contains('..')) {
        attachmentWarnings.add('第 ${row.lineNumber} 行：附件名「$name」不合法，已跳过');
        continue;
      }
      if (!availableAttachments.containsKey(name)) {
        attachmentWarnings.add('第 ${row.lineNumber} 行：包里缺少附件「$name」');
        continue;
      }
      usedAttachments.add(name);
    }

    entries.add(PlannedEntry(row: row, dedupeKey: key));
  }

  // 父分类必须先建：把带 parentName 的排在后面
  newCategories.sort((a, b) {
    if (a.parentName == null && b.parentName != null) return -1;
    if (a.parentName != null && b.parentName == null) return 1;
    return 0;
  });

  var attachmentBytes = 0;
  for (final name in usedAttachments) {
    attachmentBytes += availableAttachments[name] ?? 0;
  }

  return ImportPlan(
    entries: entries,
    skipped: skipped,
    newCategories: newCategories,
    newAccounts: newAccounts,
    newTags: newTags,
    attachmentFiles: usedAttachments.toList(),
    attachmentBytes: attachmentBytes,
    attachmentWarnings: attachmentWarnings,
    totalRows: parsed.totalRows,
  );
}
