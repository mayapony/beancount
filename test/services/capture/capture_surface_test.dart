import 'package:bean_count/data/db/app_database.dart';
import 'package:bean_count/data/db/connection.dart';
import 'package:bean_count/data/repositories/app_state_repository.dart';
import 'package:bean_count/services/capture/capture_surface.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late AppDatabase db;
  late CaptureSurfaceStore store;

  setUp(() async {
    db = AppDatabase(openInMemoryConnection());
    store = CaptureSurfaceStore(AppStateRepository(db));
    await db.select(db.appState).get();
  });

  tearDown(() async => db.close());

  test('默认无标记', () async {
    expect(await store.isMarked('com.tencent.mm', 'fp-1'), isFalse);
  });

  test('mark 后 isMarked 命中，跨包不误判', () async {
    await store.mark('com.tencent.mm', 'fp-1');

    expect(await store.isMarked('com.tencent.mm', 'fp-1'), isTrue);
    expect(await store.isMarked('com.tencent.mm', 'fp-2'), isFalse);
    expect(await store.isMarked('com.eg.android.AlipayGphone', 'fp-1'), isFalse);
  });

  test('mark 幂等', () async {
    await store.mark('com.tencent.mm', 'fp-1');
    await store.mark('com.tencent.mm', 'fp-1');
    await store.mark('com.tencent.mm', 'fp-2');

    expect(await store.load(), {'com.tencent.mm|fp-1', 'com.tencent.mm|fp-2'});
  });
}
