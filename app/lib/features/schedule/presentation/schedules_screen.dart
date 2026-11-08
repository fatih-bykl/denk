import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/date/dates.dart';
import '../../../core/money/money.dart';
import '../../../core/widgets/async_body.dart';
import '../application/schedule_providers.dart';
import '../domain/payment_schedule.dart';
import 'schedule_form_sheet.dart';

/// Tüm ödeme planlarının listesi.
class SchedulesScreen extends ConsumerWidget {
  const SchedulesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final schedules = ref.watch(schedulesProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Ödeme planları')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => showScheduleForm(context),
        icon: const Icon(Icons.add),
        label: const Text('Plan ekle'),
      ),
      body: AsyncBody(
        value: schedules,
        onRetry: () => ref.invalidate(schedulesProvider),
        data: (all) {
          if (all.isEmpty) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  'Henüz ödeme planı yok.\n'
                  'Kira, fatura veya taksit gibi düzenli ödemeleri "Plan ekle" ile tanımla.',
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }
          final active = all.where((s) => s.isActive).toList();
          final inactive = all.where((s) => !s.isActive).toList();
          return ListView(
            padding: const EdgeInsets.only(bottom: 88),
            children: [
              for (final s in active) _ScheduleTile(s),
              if (inactive.isNotEmpty)
                ExpansionTile(
                  title: Text('Pasif planlar (${inactive.length})'),
                  children: [for (final s in inactive) _ScheduleTile(s)],
                ),
            ],
          );
        },
      ),
    );
  }
}

class _ScheduleTile extends StatelessWidget {
  const _ScheduleTile(this.schedule);

  final PaymentSchedule schedule;

  @override
  Widget build(BuildContext context) {
    final s = schedule;
    final ending = s.occurrenceLimit != null
        ? ' · ${s.occurrenceLimit} taksit'
        : s.endDate != null
        ? ' · ${Dates.long(s.endDate!)} tarihine kadar'
        : '';
    return ListTile(
      leading: Icon(
        s.flow == CashFlow.inflow ? Icons.arrow_downward : Icons.arrow_upward,
      ),
      title: Text(s.title),
      subtitle: Text(
        '${s.frequencyLabel} · ${Dates.long(s.startDate)}$ending',
        maxLines: 2,
      ),
      trailing: Text(Money.format(s.amount)),
      textColor: s.isActive ? null : Theme.of(context).disabledColor,
      onTap: () => showScheduleForm(context, schedule: s),
    );
  }
}
