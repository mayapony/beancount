import 'package:bean_count/data/db/app_database.dart';
import 'package:bean_count/data/db/connection.dart';
import 'package:bean_count/data/repositories/app_state_repository.dart';
import 'package:bean_count/services/capture/capture_account_map.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late AppDatabase db;
  late CaptureAccountMap map;

  setUp(() async {
    db = AppDatabase(openInMemoryConnection());
    map = CaptureAccountMap(AppStateRepository(db));
    await db.select(db.appState).get();
  });

  tearDown(() async => db.close());

  test('记住之后能查回来', () async {
    await map.remember('com.jingdong.app.mall', '银行卡', 'acc-cmb');
    expect(
      await map.lookup('com.jingdong.app.mall', '银行卡'),
      'acc-cmb',
    );
  });

  test('不同包名或渠道互不影响', () async {
    await map.remember('com.jingdong.app.mall', '银行卡', 'acc-cmb');
    await map.remember('com.eg.android.AlipayGphone', '余额宝', 'acc-yeb');

    expect(await map.lookup('com.jingdong.app.mall', '银行卡'), 'acc-cmb');
    expect(
      await map.lookup('com.eg.android.AlipayGphone', '余额宝'),
      'acc-yeb',
    );
    expect(await map.lookup('com.jingdong.app.mall', '余额宝'), isNull);
  });

  test('渠道词大小写与空格归一', () async {
    await map.remember('com.jingdong.app.mall', ' BankCard ', 'acc-cmb');
    expect(await map.lookup('com.jingdong.app.mall', 'bankcard'), 'acc-cmb');
  });

  test('没有渠道词时单独成键', () async {
    await map.remember('com.taobao.taobao', null, 'acc-a');
    expect(await map.lookup('com.taobao.taobao', null), 'acc-a');
    expect(await map.lookup('com.taobao.taobao', ''), 'acc-a');
  });

  test('坏数据不让整体失效', () async {
    final state = AppStateRepository(db);
    await state.write(CaptureAccountMap.kKey, 'not json');
    expect(await map.lookup('com.taobao.taobao', '银行卡'), isNull);

    await map.remember('com.taobao.taobao', '银行卡', 'acc-a');
    expect(await map.lookup('com.taobao.taobao', '银行卡'), 'acc-a');
  });

  test('空账户不写入', () async {
    await map.remember('com.taobao.taobao', '银行卡', '');
    expect(await map.lookup('com.taobao.taobao', '银行卡'), isNull);
  });
}
