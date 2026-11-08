import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/date/dates.dart';
import '../../../core/money/money.dart';
import '../../../core/widgets/async_body.dart';
import '../data/debts_repository.dart';
import '../domain/debt.dart';
import 'debt_detail_sheet.dart';
import 'debt_form_sheet.dart';

class DebtsScreen extends ConsumerStatefulWidget {
  const DebtsScreen({super.key});

  @override
  ConsumerState<DebtsScreen> createState() => _DebtsScreenState();
}

class _DebtsScreenState extends ConsumerState<DebtsScreen> {
  DebtDirection _direction = DebtDirection.payable;

  @override
  Widget build(BuildContext context) {
    final debts = ref.watch(debtsProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Borç / Alacak')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => showDebtForm(context, direction: _direction),
        icon: const Icon(Icons.add),
        label: const Text('Kayıt ekle'),
      ),
      body: AsyncBody(
        value: debts,
        onRetry: () => ref.invalidate(debtsProvider),
        data: (all) {
          int openTotal(DebtDirection d) => all
              .where((x) => x.direction == d && !x.isClosed)
              .fold(
                0,
                (s, x) => s + (x.remainingAmount > 0 ? x.remainingAmount : 0),
              );
          final shown = all.where((d) => d.direction == _direction).toList();
          final open = shown.where((d) => !d.isClosed).toList();
          final closed = shown.where((d) => d.isClosed).toList();

          return ListView(
            padding: const EdgeInsets.only(bottom: 88),
            children: [
              _Totals(
                payable: openTotal(DebtDirection.payable),
                receivable: openTotal(DebtDirection.receivable),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: SegmentedButton<DebtDirection>(
                  segments: [
                    for (final d in DebtDirection.values)
                      ButtonSegment(value: d, label: Text(d.plural)),
                  ],
                  selected: {_direction},
                  onSelectionChanged: (s) =>
                      setState(() => _direction = s.first),
                ),
              ),
              const SizedBox(height: 8),
              if (open.isEmpty)
                Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(
                    _direction == DebtDirection.payable
                        ? 'Açık borcun yok.'
                        : 'Açık alacağın yok.',
                    textAlign: TextAlign.center,
                  ),
                ),
              for (final d in open) _DebtTile(d),
              if (closed.isNotEmpty)
                ExpansionTile(
                  title: Text('Kapananlar (${closed.length})'),
                  children: [for (final d in closed) _DebtTile(d)],
                ),
            ],
          );
        },
      ),
    );
  }
}

class _Totals extends StatelessWidget {
  const _Totals({required this.payable, required this.receivable});

  final int payable;
  final int receivable;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    Widget cell(String label, int value, Key key) => Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: theme.textTheme.labelMedium),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              Money.format(value),
              key: key,
              style: theme.textTheme.titleLarge,
            ),
          ),
        ],
      ),
    );
    return Card(
      margin: const EdgeInsets.all(16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            cell('Toplam borcum', payable, const Key('total-payable')),
            cell('Toplam alacağım', receivable, const Key('total-receivable')),
          ],
        ),
      ),
    );
  }
}

class _DebtTile extends ConsumerWidget {
  const _DebtTile(this.debt);

  final Debt debt;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final today = ref.watch(todayProvider);
    final upcoming = debt.upcomingDate;
    final overdue =
        !debt.isClosed && upcoming != null && upcoming.isBefore(today);
    final dateText = upcoming == null
        ? null
        : '${debt.hasInstallments ? 'Sıradaki taksit' : 'Vade'}: '
              '${Dates.long(upcoming)}';

    return ListTile(
      title: Text(debt.counterparty),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            [
              debt.title,
              if (debt.hasInstallments) '${debt.installmentCount} taksit',
            ].join(' · '),
          ),
          const SizedBox(height: 6),
          LinearProgressIndicator(
            value: debt.progress,
            borderRadius: BorderRadius.circular(4),
          ),
          if (dateText != null) ...[
            const SizedBox(height: 4),
            Text(
              dateText,
              style: theme.textTheme.bodySmall?.copyWith(
                color: overdue ? theme.colorScheme.error : null,
              ),
            ),
          ],
        ],
      ),
      trailing: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(
            Money.format(debt.remainingAmount),
            style: theme.textTheme.titleMedium,
          ),
          Text('kalan', style: theme.textTheme.labelSmall),
        ],
      ),
      textColor: debt.isClosed ? theme.disabledColor : null,
      onTap: () => showDebtDetail(context, debt),
    );
  }
}
