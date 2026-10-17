import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:bean_count/data/db/app_database.dart';
import 'package:bean_count/data/db/connection.dart';
import 'package:bean_count/data/repositories/attachment_repository.dart';
import 'package:bean_count/data/repositories/transaction_repository.dart';
import 'package:bean_count/pages/export_page.dart';
import 'package:bean_count/services/export/export_service.dart';
import 'package:bean_count/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// 导出页只关心「状态机 + 保存结果」，产物本身由 export_service_test 覆盖；
/// 这里用假服务避免在 widget test 的假时钟里做真实文件 IO。
class _FakeExportService extends ExportService {
  _FakeExportService({
    required super.transactions,
    required super.attachments,
    this.entries = 1,
    this.images = 1,
    this.buildError,
  });

  final int entries;
  final int images;
  final String? buildError;

  @override
  Future<ExportSummary> summary() async =>
      ExportSummary(entryCount: entries, imageCount: images);

  @override
  Future<ExportFile> buildCsv() async {
    if (buildError != null) throw StateError(buildError!);
    return ExportFile(
      fileName: 'beecount_20261018_011500.csv',
      bytes: Uint8List.fromList(<int>[1, 2, 3]),
      entryCount: entries,
      imageCount: 0,
    );
  }

  @override
  Future<ExportFile> buildBackup() async {
    if (buildError != null) throw StateError(buildError!);
    return ExportFile(
      fileName: 'beancount_backup_20261018_011500.zip',
      bytes: Uint8List.fromList(<int>[4, 5, 6, 7]),
      entryCount: entries,
      imageCount: images,
    );
  }
}

void main() {
  late AppDatabase db;
  late TransactionRepository repo;
  late AttachmentRepository attachments;
  late Directory tmp;

  setUp(() async {
    db = AppDatabase(openInMemoryConnection());
    tmp = await Directory.systemTemp.createTemp('bean_export_page');
    attachments = AttachmentRepository(db, directory: tmp);
    repo = TransactionRepository(db, attachments: attachments);
    await db.select(db.transactions).get();
  });

  tearDown(() async {
    await db.close();
    if (await tmp.exists()) await tmp.delete(recursive: true);
  });

  Future<void> pumpPage(
    WidgetTester tester, {
    required ExportSaver save,
    ExportService? service,
  }) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.75;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        theme: buildBeanTheme(Brightness.light),
        home: ExportPage(
          service: service ??
              _FakeExportService(transactions: repo, attachments: attachments),
          save: save,
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
  }

  testWidgets('打开即显示规模与两个导出入口', (tester) async {
    await pumpPage(
      tester,
      save: (_) async => null,
      service: _FakeExportService(
        transactions: repo,
        attachments: attachments,
        entries: 48,
        images: 46,
      ),
    );

    expect(find.text('48 笔账 · 46 张图'), findsOneWidget);
    expect(find.text('导出 CSV'), findsOneWidget);
    expect(find.text('完整备份 zip'), findsOneWidget);
  });

  testWidgets('导出 CSV 成功后显示文件名、大小与位置', (tester) async {
    ExportFile? saved;
    await pumpPage(
      tester,
      save: (file) async {
        saved = file;
        return '下载/beecount_20261018_011500.csv';
      },
    );

    await tester.tap(find.text('导出 CSV'));
    await tester.pumpAndSettle();

    expect(saved, isNotNull);
    expect(saved!.fileName, 'beecount_20261018_011500.csv');
    expect(saved!.entryCount, 1);
    expect(find.text('已导出 beecount_20261018_011500.csv'), findsOneWidget);
    expect(find.textContaining('下载/beecount'), findsOneWidget);
  });

  testWidgets('取消保存不显示成功、按钮恢复可点', (tester) async {
    await pumpPage(tester, save: (_) async => null);

    await tester.tap(find.text('完整备份 zip'));
    await tester.pumpAndSettle();

    expect(find.textContaining('已导出'), findsNothing);
    expect(find.text('完整备份 zip'), findsOneWidget);
  });

  testWidgets('保存失败显示可读原因，不显示成功', (tester) async {
    await pumpPage(
      tester,
      save: (_) async => throw const FileSystemException('磁盘已满'),
    );

    await tester.tap(find.text('导出 CSV'));
    await tester.pumpAndSettle();

    expect(find.textContaining('导出失败：'), findsOneWidget);
    expect(find.textContaining('已导出'), findsNothing);
  });

  testWidgets('打包失败也走失败态', (tester) async {
    await pumpPage(
      tester,
      save: (_) async => '不该走到保存',
      service: _FakeExportService(
        transactions: repo,
        attachments: attachments,
        buildError: '打包中断',
      ),
    );

    await tester.tap(find.text('完整备份 zip'));
    await tester.pumpAndSettle();

    expect(find.textContaining('导出失败：'), findsOneWidget);
  });

  testWidgets('打包中两个按钮都不可点，结束后恢复', (tester) async {
    var calls = 0;
    final completer = Completer<String?>();
    await pumpPage(
      tester,
      save: (_) {
        calls++;
        return completer.future;
      },
    );

    await tester.tap(find.text('完整备份 zip'));
    await tester.pump();
    expect(find.textContaining('正在打包'), findsOneWidget);

    // 打包期间再点两个入口，都不该触发第二次保存
    await tester.tap(find.text('完整备份 zip'));
    await tester.pump();
    await tester.tap(find.text('导出 CSV'));
    await tester.pump();
    expect(calls, 1);

    completer.complete('下载/beancount_backup.zip');
    await tester.pumpAndSettle();

    expect(find.textContaining('正在打包'), findsNothing);
    expect(find.textContaining('已导出 beancount_backup'), findsOneWidget);
  });
}
