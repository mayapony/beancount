import 'package:bean_count/data/db/app_database.dart';
import 'package:bean_count/data/db/connection.dart';
import 'package:bean_count/data/repositories/attachment_repository.dart';
import 'package:bean_count/pages/shell.dart';
import 'package:bean_count/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'dart:io';

void main() {
  late AppDatabase db;
  late AttachmentRepository attachments;
  late Directory tmp;

  setUp(() async {
    db = AppDatabase(openInMemoryConnection());
    tmp = await Directory.systemTemp.createTemp('bean_fab');
    attachments = AttachmentRepository(db, directory: tmp);
    await db.select(db.transactions).get();
  });

  tearDown(() async {
    await db.close();
    if (await tmp.exists()) await tmp.delete(recursive: true);
  });

  Future<void> pumpShell(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        theme: buildBeanTheme(Brightness.light),
        home: ShellPage(database: db, attachmentRepository: attachments),
      ),
    );
    await tester.pump();
    await tester.pump();
  }

  testWidgets('金豆的上半圆也能点开记一笔（曾经点不动）', (tester) async {
    await pumpShell(tester);

    // 金豆圆心正好落在底栏顶边：向上半个身位在底栏盒子之外。
    // 这里点上半圆，而不是圆心。
    final fab = find.byIcon(Icons.add_rounded);
    final center = tester.getCenter(fab);
    await tester.tapAt(center - const Offset(0, 20));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('记一笔'), findsOneWidget);
  });

  testWidgets('金豆的下半圆同样可点（底栏内的命中区）', (tester) async {
    await pumpShell(tester);

    final fab = find.byIcon(Icons.add_rounded);
    final center = tester.getCenter(fab);
    await tester.tapAt(center + const Offset(0, 20));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('记一笔'), findsOneWidget);
  });
}
