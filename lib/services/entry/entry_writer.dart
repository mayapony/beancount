import '../../data/db/enums.dart';
import '../../data/repositories/attachment_repository.dart';
import '../../data/repositories/transaction_repository.dart';
import '../attachments/image_picker_service.dart';

/// 提交一笔账：**先写交易，再挂图片**。
///
/// 顺序很重要：
/// - 交易没写成（命中去重）时不能留图片，否则就是孤儿文件；
/// - 交易写成后逐张落盘，附件目录只放"已保存的账"的图。
class EntryWriter {
  EntryWriter({
    required TransactionRepository transactions,
    required AttachmentRepository attachments,
  })  : _transactions = transactions,
        _attachments = attachments;

  final TransactionRepository _transactions;
  final AttachmentRepository _attachments;

  Future<CreateResult> submit({
    required EntryType type,
    required int amountCents,
    required DateTime happenedAt,
    String? categoryId,
    String? accountId,
    String? toAccountId,
    String note = '',
    List<String> tags = const <String>[],
    List<PickedImage> images = const <PickedImage>[],
  }) async {
    final result = await _transactions.create(
      NewTransaction(
        type: type,
        amountCents: amountCents,
        categoryId: categoryId,
        accountId: accountId,
        toAccountId: toAccountId,
        happenedAt: happenedAt,
        note: note,
        tags: tags,
      ),
    );

    // 命中去重：账没新增，图片也不该多出来
    if (!result.inserted) return result;

    for (var i = 0; i < images.length; i++) {
      await _attachments.add(
        transactionId: result.transactionId,
        bytes: images[i].bytes,
        fileName: images[i].fileName,
        sortOrder: i,
      );
    }
    return result;
  }
}
