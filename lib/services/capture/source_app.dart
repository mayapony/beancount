library;

/// 来源应用包名 → 界面上的可读名。
///
/// 只认常见的那几个；认不出就原样显示包名——宁可显示 `com.foo.bar`，也不猜一个
/// 可能错的中文名。这里不引入 package_info / PackageManager，是为了让这段逻辑
/// 在纯 Dart 测试里也能跑。
const _knownApps = {
  'com.tencent.mm': '微信',
  'com.eg.android.AlipayGphone': '支付宝',
  'com.taobao.taobao': '淘宝',
  'com.taobao.idlefish': '闲鱼',
  'com.jingdong.app.mall': '京东',
  'com.xunmeng.pinduoduo': '拼多多',
  'com.sankuai.meituan': '美团',
  'com.sankuai.meituan.takeoutnew': '美团外卖',
  'com.sdu.didi.psnger': '滴滴出行',
  'com.xiaomi.shop': '小米商城',
  'com.MobileTicket': '铁路 12306',
  'cn.samsclub.app': '山姆会员店',
  'com.autonavi.minimap': '高德地图',
  'com.netease.cloudmusic': '网易云音乐',
};

/// 包名对应的应用名；为空时返回空串，未知包名原样返回。
String sourceAppName(String? packageName) {
  if (packageName == null || packageName.isEmpty) return '';
  return _knownApps[packageName] ?? packageName;
}
