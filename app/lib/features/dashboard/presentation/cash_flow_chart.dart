import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../core/money/money.dart';
import '../application/dashboard_providers.dart';

/// Gelir ve gider renkleri: sabit sırayla iki kategori rengi (önce gelir, sonra gider).
/// Renk körlüğü ve karşıtlık için uygulamanın kart yüzeyine karşı doğrulandı;
/// açık temada turuncu 3:1'in altında kaldığından değerler tabloda da gösterilir.
abstract final class CashFlowColors {
  static Color income(Brightness b) =>
      b == Brightness.light ? const Color(0xFF2A78D6) : const Color(0xFF3987E5);
  static Color expense(Brightness b) =>
      b == Brightness.light ? const Color(0xFFEB6834) : const Color(0xFFD95926);
}

/// Eksen aralığı için yuvarlak adım: 1, 2, 2,5 veya 5 × 10ⁿ (ör. 8.600 → 10.000).
double niceStep(double raw) {
  if (raw <= 0) return 1;
  var magnitude = 1.0;
  while (magnitude * 10 <= raw) {
    magnitude *= 10;
  }
  while (magnitude > raw) {
    magnitude /= 10;
  }
  for (final m in const [1.0, 2.0, 2.5, 5.0, 10.0]) {
    if (m * magnitude >= raw) return m * magnitude;
  }
  return 10 * magnitude;
}

/// Son aylarda gelir ve giderin yan yana çubuklarla karşılaştırması.
class CashFlowChart extends StatelessWidget {
  const CashFlowChart({super.key, required this.months});

  final List<MonthFlow> months;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final brightness = theme.brightness;
    final incomeColor = CashFlowColors.income(brightness);
    final expenseColor = CashFlowColors.expense(brightness);
    final muted = theme.colorScheme.onSurfaceVariant;
    final monthFormat = DateFormat('MMM', 'tr_TR');
    final compact = NumberFormat.compact(locale: 'tr_TR');

    final maxKurus = months.fold<int>(
      0,
      (m, f) => [m, f.income, f.expense].reduce((a, b) => a > b ? a : b),
    );
    final step = niceStep(maxKurus / 100 / 4);
    // Eksen yuvarlak bir değerde biter; en yüksek çubuğun üstünde biraz boşluk kalır.
    final maxY = step * ((maxKurus / 100) / step + 0.25).ceilToDouble();

    BarChartRodData rod(int kurus, Color color) => BarChartRodData(
      toY: kurus / 100,
      color: color,
      width: 10,
      borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            _LegendDot(color: incomeColor, label: 'Gelir'),
            const SizedBox(width: 16),
            _LegendDot(color: expenseColor, label: 'Gider'),
          ],
        ),
        const SizedBox(height: 12),
        SizedBox(
          height: 180,
          child: BarChart(
            BarChartData(
              maxY: maxY,
              minY: 0,
              alignment: BarChartAlignment.spaceAround,
              borderData: FlBorderData(show: false),
              gridData: FlGridData(
                drawVerticalLine: false,
                horizontalInterval: step,
                getDrawingHorizontalLine: (_) => FlLine(
                  color: theme.colorScheme.outlineVariant.withValues(
                    alpha: 0.5,
                  ),
                  strokeWidth: 1,
                ),
              ),
              titlesData: FlTitlesData(
                topTitles: const AxisTitles(),
                rightTitles: const AxisTitles(),
                leftTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 44,
                    interval: step,
                    getTitlesWidget: (value, meta) => value == meta.max
                        ? const SizedBox.shrink()
                        : Text(
                            compact.format(value),
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: muted,
                            ),
                          ),
                  ),
                ),
                bottomTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    getTitlesWidget: (value, meta) => Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(
                        monthFormat.format(months[value.toInt()].month),
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: muted,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              barTouchData: BarTouchData(
                touchTooltipData: BarTouchTooltipData(
                  getTooltipColor: (_) => theme.colorScheme.inverseSurface,
                  getTooltipItem: (group, groupIndex, rod, rodIndex) {
                    final f = months[group.x];
                    return BarTooltipItem(
                      '${DateFormat('MMMM y', 'tr_TR').format(f.month)}\n'
                      '${rodIndex == 0 ? 'Gelir' : 'Gider'}: '
                      '${Money.format(rodIndex == 0 ? f.income : f.expense)}',
                      TextStyle(
                        color: theme.colorScheme.onInverseSurface,
                        fontSize: 12,
                      ),
                    );
                  },
                ),
              ),
              barGroups: [
                for (var i = 0; i < months.length; i++)
                  BarChartGroupData(
                    x: i,
                    barsSpace: 2,
                    barRods: [
                      rod(months[i].income, incomeColor),
                      rod(months[i].expense, expenseColor),
                    ],
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        _CashFlowTable(months: months),
      ],
    );
  }
}

class _LegendDot extends StatelessWidget {
  const _LegendDot({required this.color, required this.label});

  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Container(
        width: 10,
        height: 10,
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(2),
        ),
      ),
      const SizedBox(width: 6),
      Text(label, style: Theme.of(context).textTheme.labelMedium),
    ],
  );
}

/// Grafikteki değerlerin tablo hâli (renge dayanmadan okunabilsin diye).
class _CashFlowTable extends StatelessWidget {
  const _CashFlowTable({required this.months});

  final List<MonthFlow> months;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final head = theme.textTheme.labelSmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    final body = theme.textTheme.bodySmall;
    final monthFormat = DateFormat('MMMM', 'tr_TR');
    TableRow row(List<Widget> cells) => TableRow(
      children: [
        for (final c in cells)
          Padding(padding: const EdgeInsets.symmetric(vertical: 3), child: c),
      ],
    );
    Widget num(String s, TextStyle? style, {Key? key}) =>
        Text(s, key: key, style: style, textAlign: TextAlign.end);

    return Table(
      columnWidths: const {0: FlexColumnWidth(1.2)},
      children: [
        row([
          Text('Ay', style: head),
          num('Gelir', head),
          num('Gider', head),
          num('Net', head),
        ]),
        for (final f in months.reversed)
          row([
            Text(monthFormat.format(f.month), style: body),
            num(Money.format(f.income, symbol: false), body),
            num(Money.format(f.expense, symbol: false), body),
            num(
              Money.format(f.net, symbol: false),
              body?.copyWith(color: f.net < 0 ? theme.colorScheme.error : null),
              key: Key('net-${f.month.year}-${f.month.month}'),
            ),
          ]),
      ],
    );
  }
}
