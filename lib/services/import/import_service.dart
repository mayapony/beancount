import '../../data/db/app_database.dart';
import '../../data/db/enums.dart';
import '../../data/repositories/account_repository.dart';
import '../../data/repositories/attachment_repository.dart';
import '../../data/repositories/category_repository.dart';
import '../../data/repositories/transaction_repository.dart';
import 'bee_count_archive.dart';
import 'import_models.dart';
import 'import_planner.dart';
import 'import_report.dart';

/// 导入执行器：把 [ImportPlan] 落库（分类/账户/标签/交易/附件）。
///
/// 三件事必须成立：
/// 1. 计划里的数字就是最终写入的数字（预览 = 结果）；
/// 2. 同一份文件导两次，第二次新增 0；
/// 3. 单行出错不拖垮整批，错误带行号。
class ImportService {
  ImportService({
    required AppDatabase db,
    required CategoryRepository categories,
    required AccountRepository accounts,
    required TransactionRepository transactions,
    required AttachmentRepository attachments,
  })  : _db = db,
        _categories = categories,
        _accounts = accounts,
        _transactions = transactions,
        _attachments = attachments;

  final AppDatabase _db;
  final CategoryRepository _categories;
  final AccountRepository _accounts;
  final TransactionRepository _transactions;
  final AttachmentRepository _attachments;

  /// 每 200 行一个事务：既不会长时间占锁，也不会一次开太多 SQL 变量。
  static const _chunkSize = 200;

  /// 读取本地现状，给 [buildImportPlan] 用。
  Future<ExistingLedger> snapshot() async {
    final categories = await _categories.allCategories();
    final accounts = await _accounts.all();
    final tags = await _db.select(_db.tags).get();
    final dedupeKeys = await _transactions.dedupeKeys();
    return ExistingLedger(
      categories: categories,
      accounts: accounts,
      tagNames: {for (final t in tags) t.name},
      dedupeKeys: dedupeKeys,
    );
  }

  /// 执行计划。
  Future<ImportReport> apply(
    ImportPlan plan, {
    required Map<String, ExtractedAttachment> attachments,
    void Function(int done, int total)? onProgress,
  }) async {
    final watch = Stopwatch()..start();
    final failures = <SkippedRow>[];

    // ── 1. 先建分类（父在前），拿到名字 → id 的缓存 ──────
    final categoryIds = <String, String>{};
    for (final category in await _categories.allCategories()) {
      categoryIds[_categoryKey(
        category.type,
        category.name,
        parentId: category.parentId,
      )] = category.id;
    }

    for (final pending in plan.newCategories) {
      final parentId = pending.parentName == null
          ? null
          : categoryIds['${pending.type.name}/${pending.parentName}'];
      final created = await _categories.ensure(
        name: pending.name,
        type: pending.type,
        parentId: parentId,
      );
      categoryIds[_categoryKey(
        pending.type,
        pending.name,
        parentId: parentId,
      )] = created.id;
    }

    // ── 2. 账户：新账户初始余额 0 ──────────────────────
    final accountIds = <String, String>{
      for (final a in await _accounts.all()) a.name: a.id,
    };
    for (final name in plan.newAccounts) {
      final created = await _accounts.ensure(name: name);
      accountIds[name] = created.id;
    }

    // ── 3. 交易：分块事务 + 附件 ───────────────────────
    var inserted = 0;
    var attachmentsSaved = 0;
    var attachmentsMissing = 0;
    var done = 0;

    for (var start = 0; start < plan.entries.length; start += _chunkSize) {
      final end = (start + _chunkSize).clamp(0, plan.entries.length);
      final chunk = plan.entries.sublist(start, end);

      await _db.transaction(() async {
        for (final entry in chunk) {
          final row = entry.row;
          try {
            final categoryType = row.type == EntryType.income
                ? CategoryType.income
                : CategoryType.expense;
            final parentId = row.subcategoryName.isEmpty
                ? null
                : categoryIds['${categoryType.name}/${row.categoryName}'];
            final categoryId = row.subcategoryName.isEmpty
                ? categoryIds['${categoryType.name}/${row.categoryName}']
                : categoryIds[_categoryKey(
                    categoryType,
                    row.subcategoryName,
                    parentId: parentId,
                  )];
            if (categoryId == null) {
              throw StateError('分类没建成：${row.categoryName}');
            }

            final result = await _transactions.create(
              NewTransaction(
                type: row.type,
                amountCents: row.amountCents,
                categoryId: categoryId,
                accountId: accountIds[row.accountName.trim()],
                happenedAt: row.happenedAt,
                note: row.note,
                tags: row.tags,
                source: EntrySource.import,
              ),
            );

            if (!result.inserted) {
              failures.add(SkippedRow(
                lineNumber: row.lineNumber,
                reason: '写入时命中去重键（库里已有相同记录）',
                summary: row.note,
              ));
              continue;
            }
            inserted++;

            for (final fileName in row.attachments) {
              final payload = attachments[fileName];
              if (payload == null) {
                attachmentsMissing++;
                continue;
              }
              await _attachments.add(
                transactionId: result.transactionId,
                bytes: payload.bytes,
                fileName: payload.fileName,
                originalName: payload.originalName,
              );
              attachmentsSaved++;
            }
          } catch (error) {
            failures.add(SkippedRow(
              lineNumber: row.lineNumber,
              reason: '$error',
              summary: row.note,
            ));
          }
          done++;
          onProgress?.call(done, plan.entries.length);
        }
      });
    }

    // ── 4. 清理：只有真的写过图才需要扫目录（也避免纯 CSV 导入做多余的 IO）
    if (attachmentsSaved > 0) {
      await _attachments.sweepOrphans();
    }

    watch.stop();
    return ImportReport(
      totalRows: plan.totalRows,
      inserted: inserted,
      skipped: plan.skipped.length,
      failures: failures,
      skipReasons: {
        for (final item in plan.skipped)
          item.reason: (plan.skipReasons[item.reason] ?? 0),
      },
      attachmentsSaved: attachmentsSaved,
      attachmentsMissing: attachmentsMissing,
      newCategories: plan.newCategories.length,
      newAccounts: plan.newAccounts.length,
      newTags: plan.newTags.length,
      elapsed: watch.elapsed,
    );
  }

  String _categoryKey(
    CategoryType type,
    String name, {
    String? parentId,
  }) =>
      parentId == null ? '${type.name}/$name' : '$parentId/$name';
}

/// 给 UI 用的入口：一次调用完成"读现状 → 建计划"，预览阶段只做这一步。
Future<ImportPlan> planImport({
  required ImportService service,
  required ParseResult parsed,
  required Map<String, int> attachmentSizes,
}) async {
  final existing = await service.snapshot();
  return buildImportPlan(
    parsed: parsed,
    existing: existing,
    availableAttachments: attachmentSizes,
  );
}
