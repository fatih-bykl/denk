import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../../../core/money/money.dart';
import '../../categories/presentation/category_icons.dart';
import '../application/category_breakdown.dart';

/// Kategori grafiklerinin renkleri: sabit sırayla altı kategorik renk + "Diğer" için gri.
/// Sıra, renk körlüğünde yan yana dilimlerin ayırt edilebilmesi için doğrulanmış
/// sıradır (koyu temada tüm kontroller geçer; açık temada bazı renkler 3:1'in altında
/// kaldığından her dilimin adı, tutarı ve yüzdesi listede yazıyla da verilir).
abstract final class ChartPalette {
  static const _light = [
    Color(0xFF2A78D6), // mavi
    Color(0xFFEB6834), // turuncu
    Color(0xFF1BAF7A), // deniz yeşili
    Color(0xFFEDA100), // sarı
    Color(0xFFE87BA4), // pembe
    Color(0xFF008300), // yeşil
  ];
  static const _dark = [
    Color(0xFF3987E5),
    Color(0xFFD95926),
    Color(0xFF199E70),
    Color(0xFFC98500),
    Color(0xFFD55181),
    Color(0xFF008300),
  ];

  static Color slot(int i, Brightness b) =>
      (b == Brightness.light ? _light : _dark)[i];

  static Color other(Brightness b) =>
      b == Brightness.light ? const Color(0xFF9A9993) : const Color(0xFF6F6E69);
}

/// Grafikteki bir dilim: ilk [maxChartSlices] kategori ayrı, kalanı "Diğer".
class DonutSlice {
  const DonutSlice({
    required this.label,
    required this.amount,
    required this.share,
    required this.color,
    this.isOther = false,
  });

  final String label;
  final int amount;
  final double share;
  final Color color;
  final bool isOther;
}

List<DonutSlice> slicesOf(CategoryBreakdown data, Brightness b) {
  final items = data.items;
  final head = items.take(maxChartSlices).toList();
  final rest = items.skip(maxChartSlices).toList();
  return [
    for (var i = 0; i < head.length; i++)
      DonutSlice(
        label: head[i].name,
        amount: head[i].amount,
        share: head[i].share,
        color: ChartPalette.slot(i, b),
      ),
    if (rest.isNotEmpty)
      DonutSlice(
        label: rest.length == 1 ? rest.single.name : 'Diğer',
        amount: rest.fold(0, (s, c) => s + c.amount),
        share: rest.fold(0.0, (s, c) => s + c.share),
        color: ChartPalette.other(b),
        isOther: true,
      ),
  ];
}

/// Listedeki bir kategorinin grafikteki rengi (ilk [maxChartSlices] kategoriden
/// sonrakiler "Diğer" dilimindedir, gri). Renkler hiçbir zaman başa dönmez.
Color colorOfItem(int index, Brightness b) => index < maxChartSlices
    ? ChartPalette.slot(index, b)
    : ChartPalette.other(b);

/// "%24" — küçük paylarda bir ondalık ("%0,5").
String percent(double share) {
  final p = share * 100;
  if (p > 0 && p < 1) return '%${p.toStringAsFixed(1).replaceAll('.', ',')}';
  return '%${p.round()}';
}

/// Kategorilere göre dağılım halkası. Dilime dokununca dilim büyür ve ortada o
/// kategorinin adı, tutarı ve payı görünür; tekrar dokununca toplama döner.
class CategoryDonut extends StatefulWidget {
  const CategoryDonut({
    super.key,
    required this.slices,
    required this.total,
    required this.totalLabel,
  });

  final List<DonutSlice> slices;
  final int total;
  final String totalLabel;

  @override
  State<CategoryDonut> createState() => _CategoryDonutState();
}

class _CategoryDonutState extends State<CategoryDonut> {
  int? _selected;

  @override
  void didUpdateWidget(CategoryDonut old) {
    super.didUpdateWidget(old);
    if (_selected != null && _selected! >= widget.slices.length) {
      _selected = null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final selected = _selected == null ? null : widget.slices[_selected!];

    return LayoutBuilder(
      builder: (context, box) {
        final size = math.min(box.maxWidth, 300.0);
        final radius = size * 0.15;
        final hole = size * 0.25;
        return SizedBox(
          height: size,
          child: Stack(
            alignment: Alignment.center,
            children: [
              PieChart(
                PieChartData(
                  startDegreeOffset: -90,
                  sectionsSpace: 2,
                  centerSpaceRadius: hole,
                  pieTouchData: PieTouchData(
                    touchCallback: (event, response) {
                      if (event is! FlTapUpEvent) return;
                      final i = response?.touchedSection?.touchedSectionIndex;
                      setState(() {
                        _selected = (i == null || i < 0 || i == _selected)
                            ? null
                            : i;
                      });
                    },
                  ),
                  sections: [
                    for (var i = 0; i < widget.slices.length; i++)
                      _section(i, radius, theme),
                  ],
                ),
                duration: const Duration(milliseconds: 250),
              ),
              IgnorePointer(
                child: SizedBox(
                  width: hole * 1.7,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        selected?.label ?? widget.totalLabel,
                        key: const Key('donut-center-label'),
                        textAlign: TextAlign.center,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.labelMedium?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 2),
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(
                          Money.format(selected?.amount ?? widget.total),
                          key: const Key('donut-center-amount'),
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      if (selected != null)
                        Text(
                          percent(selected.share),
                          style: theme.textTheme.labelMedium,
                        ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  PieChartSectionData _section(int i, double radius, ThemeData theme) {
    final s = widget.slices[i];
    final isSelected = i == _selected;
    final dimmed = _selected != null && !isSelected;
    // Seçici doğrudan etiket: yalnızca %8 ve üzeri dilimlerde, halkanın dışında.
    final showLabel = s.share >= 0.08;
    return PieChartSectionData(
      value: s.amount.toDouble(),
      color: dimmed ? s.color.withValues(alpha: 0.35) : s.color,
      radius: isSelected ? radius + 8 : radius,
      showTitle: false,
      badgeWidget: showLabel
          ? Text(
              percent(s.share),
              style: theme.textTheme.labelMedium?.copyWith(
                fontWeight: FontWeight.w700,
                color: dimmed
                    ? theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.5)
                    : theme.colorScheme.onSurface,
              ),
            )
          : null,
      badgePositionPercentageOffset: 1.42,
    );
  }
}

/// Tasarruf oranı halkası: (gelir − gider) / gelir. Gelir yoksa gösterilmez.
class SavingsMeter extends StatelessWidget {
  const SavingsMeter({super.key, required this.income, required this.expense});

  final int income;
  final int expense;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final rate = (income - expense) / income;
    final negative = rate < 0;
    final color = negative
        ? theme.colorScheme.error
        : theme.colorScheme.primary;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: 56,
          height: 56,
          child: Stack(
            alignment: Alignment.center,
            children: [
              CircularProgressIndicator(
                value: rate.abs().clamp(0, 1).toDouble(),
                strokeWidth: 6,
                strokeCap: StrokeCap.round,
                color: color,
                backgroundColor: color.withValues(alpha: 0.18),
              ),
              Text(
                percent(rate.abs()),
                key: const Key('savings-rate'),
                style: theme.textTheme.labelLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 10),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              negative ? 'Gelirden fazla' : 'Tasarruf',
              style: theme.textTheme.labelLarge,
            ),
            Text(
              negative ? 'harcandı' : 'gelirinin',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// Kategori listesinde bir satır: renk işareti, simge, ad, tutar, pay ve
/// tek renkli pay çubuğu (çubuklar aynı tabandan karşılaştırılır).
class CategoryShareRow extends StatelessWidget {
  const CategoryShareRow({
    super.key,
    required this.item,
    required this.swatch,
    required this.maxShare,
  });

  final CategoryShare item;
  final Color swatch;

  /// Listedeki en büyük pay: en uzun çubuk satırı doldurur.
  final double maxShare;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final icon = CategoryIcons.all[item.icon] ?? Icons.label_outline;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: swatch.withValues(alpha: 0.16),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, size: 20, color: swatch),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: swatch,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        item.name,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    Text(
                      Money.format(item.amount),
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    Expanded(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: LinearProgressIndicator(
                          value: maxShare == 0 ? 0 : item.share / maxShare,
                          minHeight: 6,
                          color: theme.colorScheme.primary,
                          backgroundColor: theme.colorScheme.primary.withValues(
                            alpha: 0.12,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    SizedBox(
                      width: 44,
                      child: Text(
                        percent(item.share),
                        textAlign: TextAlign.end,
                        style: theme.textTheme.labelMedium?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
