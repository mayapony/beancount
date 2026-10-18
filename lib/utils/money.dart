import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../theme/tokens.dart';

final NumberFormat _moneyFormat = NumberFormat('#,##0.00');
final NumberFormat _compactFormat = NumberFormat('#,##0.##');

/// 千分位金额（记账硬需求：长金额必须分隔）。
String formatMoney(num value) => _moneyFormat.format(value);

String formatMoneyCompact(num value) => _compactFormat.format(value);

/// 金额文本：等宽数字（tabular）+ 千分位 + 语义色。
///
/// 设计约定：支出用默认文字色 + `-`，收入绿 + `+`，转账中性；红色只留给警示。
class AmountText extends StatelessWidget {
  const AmountText(
    this.value, {
    super.key,
    this.isIncome = false,
    this.isTransfer = false,
    this.fontSize = 16,
    this.fontWeight = FontWeight.w600,
    this.showSign = true,
    this.color,
  });

  final double value;
  final bool isIncome;
  final bool isTransfer;
  final double fontSize;
  final FontWeight fontWeight;
  final bool showSign;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final palette = BeanPalette.of(context);
    final semantic = isTransfer
        ? palette.transfer
        : (isIncome ? palette.income : palette.expense);
    final sign = !showSign
        ? (value < 0 ? '-' : '')
        : isTransfer
            ? ''
            : (isIncome ? '+' : '-');

    return Text(
      '$sign${formatMoney(value.abs())}',
      style: TextStyle(
        color: color ?? semantic,
        fontSize: fontSize,
        fontWeight: fontWeight,
        fontFeatures: const [FontFeature.tabularFigures()],
      ),
    );
  }
}
