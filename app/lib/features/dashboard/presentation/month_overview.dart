import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/routes.dart';
import '../../../core/date/dates.dart';
import '../../../core/money/money.dart';
import '../../categories/domain/category.dart';
import '../application/category_breakdown.dart';
import '../application/dashboard_providers.dart';
import 'cash_flow_chart.dart';
import 'category_donut.dart';

/// Ayın özeti: ay seçici, gelir/gider kartları, kategori halkası ve tasarruf oranı.
class MonthOverviewCard extends ConsumerWidget {
  const MonthOverviewCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final month = ref.watch(dashboardMonthProvider);
    final monthNav = ref.read(dashboardMonthProvider.notifier);
    final kind = ref.watch(dashboardKindProvider);
    final comparison = ref.watch(monthComparisonProvider(month));
    final breakdown = ref.watch(
      categoryBreakdownProvider((month: month, kind: kind)),
    );

    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 8, 8, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                IconButton(
                  tooltip: 'Önceki ay',
                  onPressed: monthNav.previous,
                  icon: const Icon(Icons.chevron_left),
                ),
                Expanded(
                  child: Text(
                    Dates.month(month),
                    key: const Key('overview-month'),
                    textAlign: TextAlign.center,
                    style: theme.textTheme.titleMedium,
                  ),
                ),
                IconButton(
                  tooltip: 'Sonraki ay',
                  onPressed: monthNav.canGoNext ? monthNav.next : null,
                  icon: const Icon(Icons.chevron_right),
                ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: switch ((comparison, breakdown)) {
                (AsyncData(value: final cmp), AsyncData(value: final data)) =>
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _FlowTiles(
                        current: cmp.current,
                        previous: cmp.previous,
                        selected: kind,
                        onSelect: ref.read(dashboardKindProvider.notifier).set,
                      ),
                      const SizedBox(height: 8),
                      if (data.isEmpty)
                        _EmptyMonth(kind: kind)
                      else
                        _DonutSection(
                          data: data,
                          kind: kind,
                          income: cmp.current.income,
                          expense: cmp.current.expense,
                        ),
                    ],
                  ),
                // Bir kaynak yüklenemezse kartta tek bir mesaj.
                (AsyncError(), _) || (_, AsyncError()) => const _LoadError(),
                _ => const SizedBox(
                  height: 360,
                  child: Center(child: CircularProgressIndicator()),
                ),
              },
            ),
          ],
        ),
      ),
    );
  }
}

/// Gelir ve gider kartları; dokunulan tür halkada gösterilir.
class _FlowTiles extends StatelessWidget {
  const _FlowTiles({
    required this.current,
    required this.previous,
    required this.selected,
    required this.onSelect,
  });

  final MonthFlow current;
  final MonthFlow previous;
  final EntryKind selected;
  final ValueChanged<EntryKind> onSelect;

  @override
  Widget build(BuildContext context) {
    final b = Theme.of(context).brightness;
    return Row(
      children: [
        Expanded(
          child: _FlowTile(
            key: const Key('tile-income'),
            label: 'Gelir',
            amount: current.income,
            previous: previous.income,
            color: CashFlowColors.income(b),
            icon: Icons.south_west,
            selected: selected == EntryKind.income,
            higherIsBetter: true,
            onTap: () => onSelect(EntryKind.income),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _FlowTile(
            key: const Key('tile-expense'),
            label: 'Gider',
            amount: current.expense,
            previous: previous.expense,
            color: CashFlowColors.expense(b),
            icon: Icons.north_east,
            selected: selected == EntryKind.expense,
            higherIsBetter: false,
            onTap: () => onSelect(EntryKind.expense),
          ),
        ),
      ],
    );
  }
}

class _FlowTile extends StatelessWidget {
  const _FlowTile({
    super.key,
    required this.label,
    required this.amount,
    required this.previous,
    required this.color,
    required this.icon,
    required this.selected,
    required this.higherIsBetter,
    required this.onTap,
  });

  final String label;
  final int amount;
  final int previous;
  final Color color;
  final IconData icon;
  final bool selected;
  final bool higherIsBetter;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final change = previous == 0 ? null : (amount - previous) / previous;
    return Material(
      color: selected
          ? color.withValues(alpha: 0.14)
          : scheme.surfaceContainerHighest.withValues(alpha: 0.5),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(
          color: selected ? color : Colors.transparent,
          width: 1.5,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.2),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(icon, size: 14, color: color),
                  ),
                  const SizedBox(width: 6),
                  Text(label, style: theme.textTheme.labelLarge),
                ],
              ),
              const SizedBox(height: 6),
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(
                  Money.format(amount),
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const SizedBox(height: 2),
              _Change(change: change, higherIsBetter: higherIsBetter),
            ],
          ),
        ),
      ),
    );
  }
}

/// "Geçen aya göre ↑ %12": artış iyi mi kötü mü, türe göre renklenir; renk tek
/// başına anlam taşımasın diye ok ve metin de vardır.
class _Change extends StatelessWidget {
  const _Change({required this.change, required this.higherIsBetter});

  final double? change;
  final bool higherIsBetter;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final style = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    final c = change;
    if (c == null) return Text('Geçen ay kayıt yok', style: style);
    if (c.abs() < 0.005) return Text('Geçen ayla aynı', style: style);
    final up = c > 0;
    final good = up == higherIsBetter;
    final color = good ? const Color(0xFF0CA30C) : theme.colorScheme.error;
    return Row(
      children: [
        Icon(
          up ? Icons.arrow_upward : Icons.arrow_downward,
          size: 13,
          color: color,
        ),
        const SizedBox(width: 2),
        Flexible(
          child: Text(
            '${percent(c.abs())} geçen aya göre',
            overflow: TextOverflow.ellipsis,
            style: style,
          ),
        ),
      ],
    );
  }
}

class _DonutSection extends StatelessWidget {
  const _DonutSection({
    required this.data,
    required this.kind,
    required this.income,
    required this.expense,
  });

  final CategoryBreakdown data;
  final EntryKind kind;
  final int income;
  final int expense;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final b = theme.brightness;
    final isExpense = kind == EntryKind.expense;
    final net = income - expense;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 8),
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: Text(
                isExpense
                    ? 'Kategorilere göre giderler'
                    : 'Kaynağına göre gelirler',
                style: theme.textTheme.titleSmall,
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  'Kalan',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                Text(
                  Money.format(net),
                  key: const Key('overview-net'),
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: net < 0 ? theme.colorScheme.error : null,
                  ),
                ),
              ],
            ),
          ],
        ),
        const SizedBox(height: 4),
        CategoryDonut(
          slices: slicesOf(data, b),
          total: data.total,
          totalLabel: isExpense ? 'Toplam gider' : 'Toplam gelir',
        ),
        if (income > 0) ...[
          const SizedBox(height: 4),
          Center(
            child: SavingsMeter(income: income, expense: expense),
          ),
        ],
      ],
    );
  }
}

/// Kategorilerin tam listesi: renk işareti (halkadaki dilim), tutar ve pay çubuğu.
class CategoryListCard extends ConsumerWidget {
  const CategoryListCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final month = ref.watch(dashboardMonthProvider);
    final kind = ref.watch(dashboardKindProvider);
    final value = ref.watch(
      categoryBreakdownProvider((month: month, kind: kind)),
    );
    final data = value.value;
    if (data == null || data.isEmpty) return const SizedBox.shrink();
    final b = theme.brightness;
    final maxShare = data.items.first.share;
    return Card(
      margin: const EdgeInsets.only(top: 12),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    kind == EntryKind.expense
                        ? 'Gider kategorileri'
                        : 'Gelir kategorileri',
                    style: theme.textTheme.titleMedium,
                  ),
                ),
                TextButton(
                  onPressed: () => context.go(Routes.transactions),
                  child: const Text('İşlemler'),
                ),
              ],
            ),
            for (var i = 0; i < data.items.length; i++)
              CategoryShareRow(
                key: Key('share-${data.items[i].name}'),
                item: data.items[i],
                swatch: colorOfItem(i, b),
                maxShare: maxShare,
              ),
          ],
        ),
      ),
    );
  }
}

class _EmptyMonth extends StatelessWidget {
  const _EmptyMonth({required this.kind});

  final EntryKind kind;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 24),
      child: Column(
        children: [
          Icon(
            Icons.donut_large,
            size: 40,
            color: theme.colorScheme.onSurfaceVariant,
          ),
          const SizedBox(height: 8),
          Text(
            kind == EntryKind.expense
                ? 'Bu ay henüz gider yok.'
                : 'Bu ay henüz gelir yok.',
            style: theme.textTheme.bodyMedium,
          ),
          TextButton(
            onPressed: () => context.go(Routes.transactions),
            child: const Text('İşlem ekle'),
          ),
        ],
      ),
    );
  }
}

class _LoadError extends StatelessWidget {
  const _LoadError();

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 8),
    child: Text(
      'Yüklenemedi. Aşağı çekerek yenile.',
      style: Theme.of(context).textTheme.bodySmall,
    ),
  );
}
