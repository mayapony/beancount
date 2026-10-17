/// Demo 用假数据 —— 仅用于展示设计风格，后续由 M1 数据层替换。
library;

class DemoTransaction {
  const DemoTransaction({
    required this.title,
    required this.categoryIndex,
    required this.time,
    required this.amount,
    this.isIncome = false,
  });

  final String title;
  final int categoryIndex;
  final String time;
  final double amount;
  final bool isIncome;
}

class DemoDayGroup {
  const DemoDayGroup({
    required this.date,
    required this.weekday,
    required this.items,
  });

  final String date;
  final String weekday;
  final List<DemoTransaction> items;

  double get expense => items
      .where((t) => !t.isIncome)
      .fold(0, (sum, t) => sum + t.amount);
}

class DemoAccount {
  const DemoAccount({
    required this.name,
    required this.type,
    required this.balance,
    required this.categoryIndex,
    this.isCredit = false,
    this.dueDay,
  });

  final String name;
  final String type;
  final double balance;
  final int categoryIndex;
  final bool isCredit;
  final int? dueDay;
}

class DemoCategoryStat {
  const DemoCategoryStat(this.categoryIndex, this.name, this.value);

  final int categoryIndex;
  final String name;
  final double value;
}

const demoDayGroups = <DemoDayGroup>[
  DemoDayGroup(
    date: '10月17日',
    weekday: '周五',
    items: [
      DemoTransaction(
        title: '楼下豆浆油条',
        categoryIndex: 0,
        time: '08:12',
        amount: 8.5,
      ),
      DemoTransaction(
        title: '地铁 2 号线',
        categoryIndex: 1,
        time: '08:45',
        amount: 4,
      ),
      DemoTransaction(
        title: '咖啡 · 美式',
        categoryIndex: 0,
        time: '14:20',
        amount: 18,
      ),
    ],
  ),
  DemoDayGroup(
    date: '10月16日',
    weekday: '周四',
    items: [
      DemoTransaction(
        title: '超市采购',
        categoryIndex: 2,
        time: '19:03',
        amount: 126.4,
      ),
      DemoTransaction(
        title: '月度工资',
        categoryIndex: 11,
        time: '10:00',
        amount: 12800,
        isIncome: true,
      ),
    ],
  ),
];

const demoAccounts = <DemoAccount>[
  DemoAccount(
    name: '日常钱包',
    type: '现金 · 微信',
    balance: 1240.55,
    categoryIndex: 0,
  ),
  DemoAccount(
    name: '招商银行卡',
    type: '储蓄卡',
    balance: 28560.00,
    categoryIndex: 9,
  ),
  DemoAccount(
    name: '招行信用卡',
    type: '信用卡',
    balance: -3280.40,
    categoryIndex: 3,
    isCredit: true,
    dueDay: 25,
  ),
];

const demoCategoryStats = <DemoCategoryStat>[
  DemoCategoryStat(0, '餐饮', 1280.5),
  DemoCategoryStat(2, '购物', 960.0),
  DemoCategoryStat(1, '交通', 420.0),
  DemoCategoryStat(3, '娱乐', 360.0),
  DemoCategoryStat(4, '居家', 240.0),
];

/// 本月每日支出（用于趋势折线）
const demoDailyTrend = <double>[
  42, 68, 51, 120, 88, 35, 96, 210, 74, 60,
  130, 92, 45, 76, 58, 140, 102, 64, 88, 150,
  70, 48, 96, 118, 82, 56, 134, 90, 66, 108,
];

/// 记账面板的分类快选顺序（高频在前，值为 BeanColors.categories 的下标）。
const kQuickCategoryOrder = <int>[
  0, 1, 2, 4, 3, 5, 6, 9, 7, 8, 10, 11,
];
