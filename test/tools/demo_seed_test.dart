import 'package:bean_count/data/db/app_database.dart';
import 'package:bean_count/data/db/connection.dart';
import 'package:flutter_test/flutter_test.dart';

import 'demo_seed.dart';

void main() {
  test('演示账本可重复播种，标签不会重复也不会丢', () async {
    final db = AppDatabase(openInMemoryConnection());
    addTearDown(db.close);

    await seedDemoLedger(db);
    for (var round = 0; round < 3; round++) {
      await resetDemoLedger(db);
      final tags = await db.select(db.tags).get();
      expect(
        tags.map((t) => t.name).toSet(),
        {'工作', '家庭', '聚餐'},
        reason: '第 $round 轮',
      );
    }
  });
}
