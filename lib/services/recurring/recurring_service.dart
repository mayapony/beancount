import '../../data/db/enums.dart';
import '../../data/repositories/recurring_repository.dart';
import '../../data/repositories/transaction_repository.dart';
import 'recurring_schedule.dart';

/// 一次补记的结果：补了几笔、跳过几期（已存在）。
class RecurringRunResult {
  const RecurringRunResult({
    required this.rules,
    required this.created,
    required this.skipped,
  });

  final int rules;
  final int created;
  final int skipped;

  bool get didNothing => created == 0;
}

/// 到期补记：把每条启用规则从起始月到当前月之间"已到日子"的期数写成真实交易。
///
/// 幂等由两层保证：
/// 1. 交易上的 `recurringRuleId + recurringPeriod` 标记（用户改过金额也还在）；
/// 2. 去重键里的 `rule:<id>:<期数>` salt（并发/重复调用兜底）。
class RecurringService {
  RecurringService({
    required RecurringRepository rules,
    required TransactionRepository transactions,
  })  : _rules = rules,
        _transactions = transactions;

  final RecurringRepository _rules;
  final TransactionRepository _transactions;

  Future<RecurringRunResult> applyDue({DateTime? now}) async {
    final reference = now ?? DateTime.now();
    final active = await _rules.allEnabled();
    var created = 0;
    var skipped = 0;

    for (final rule in active) {
      for (final at in occurrencesUntil(rule, reference)) {
        final period = periodOf(at);
        if (await _rules.hasPeriod(rule.id, period)) {
          skipped++;
          continue;
        }

        try {
          final result = await _transactions.create(
            NewTransaction(
              type: rule.type,
              amountCents: rule.amountCents,
              categoryId: rule.type == EntryType.transfer ? null : rule.categoryId,
              accountId: rule.accountId,
              toAccountId:
                  rule.type == EntryType.transfer ? rule.toAccountId : null,
              happenedAt: at,
              note: rule.note,
              recurringRuleId: rule.id,
              recurringPeriod: period,
            ),
          );
          if (result.inserted) {
            created++;
          } else {
            skipped++;
          }
        } catch (_) {
          // 单期失败（例如分类被删导致外键不满足）不拖垮其它规则
          skipped++;
        }
      }
    }

    return RecurringRunResult(
      rules: active.length,
      created: created,
      skipped: skipped,
    );
  }
}
