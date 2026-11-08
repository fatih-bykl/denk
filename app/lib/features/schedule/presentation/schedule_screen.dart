import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:table_calendar/table_calendar.dart';

import '../../../app/routes.dart';
import '../../../core/date/dates.dart';
import '../../../core/money/money.dart';
import '../../../core/widgets/async_body.dart';
import '../application/schedule_providers.dart';
import '../domain/occurrence.dart';
import '../domain/payment_schedule.dart';
import 'occurrence_sheet.dart';
import 'schedule_form_sheet.dart';

class ScheduleScreen extends ConsumerStatefulWidget {
  const ScheduleScreen({super.key});

  @override
  ConsumerState<ScheduleScreen> createState() => _ScheduleScreenState();
}

class _ScheduleScreenState extends ConsumerState<ScheduleScreen> {
  late DateTime _selected = ref.read(todayProvider);
  late DateTime _month = Dates.monthStart(_selected);

  @override
  Widget build(BuildContext context) {
    final today = ref.watch(todayProvider);
    final occurrences = ref.watch(monthOccurrencesProvider(_month));
    final overdue = ref.watch(overdueOccurrencesProvider).value ?? const [];

    return Scaffold(
      appBar: AppBar(
        title: const Text('Takvim'),
        actions: [
          TextButton.icon(
            onPressed: () => context.go(Routes.schedules),
            icon: const Icon(Icons.list_alt),
            label: const Text('Planlar'),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => showScheduleForm(context),
        icon: const Icon(Icons.add),
        label: const Text('Plan ekle'),
      ),
      body: AsyncBody(
        value: occurrences,
        // Hata dönemlerden değil planlardan/ufuk eşitlemesinden gelmiş olabilir;
        // hepsini yeniden yükle.
        onRetry: () => invalidateSchedule(ref),
        data: (items) {
          final byDay = <DateTime, List<Occurrence>>{};
          for (final o in items) {
            (byDay[o.dueDate] ??= []).add(o);
          }
          final dayItems = byDay[Dates.dateOnly(_selected)] ?? const [];
          final dueThisMonth = items
              .where((o) => o.isPending && o.flow == CashFlow.outflow)
              .fold<int>(0, (s, o) => s + o.amount);

          return ListView(
            padding: const EdgeInsets.only(bottom: 88),
            children: [
              _MonthSummary(
                dueThisMonth: dueThisMonth,
                overdueCount: overdue.length,
              ),
              TableCalendar<Occurrence>(
                locale: 'tr_TR',
                firstDay: DateTime(2000),
                lastDay: DateTime(2100, 12, 31),
                focusedDay: _selected,
                currentDay: today,
                startingDayOfWeek: StartingDayOfWeek.monday,
                availableCalendarFormats: const {CalendarFormat.month: 'Ay'},
                headerStyle: const HeaderStyle(
                  formatButtonVisible: false,
                  titleCentered: true,
                ),
                selectedDayPredicate: (day) => isSameDay(day, _selected),
                eventLoader: (day) => byDay[Dates.dateOnly(day)] ?? const [],
                onDaySelected: (selected, _) =>
                    setState(() => _selected = Dates.dateOnly(selected)),
                onPageChanged: (focused) => setState(() {
                  _month = Dates.monthStart(focused);
                  _selected = Dates.dateOnly(focused);
                }),
                calendarBuilders: CalendarBuilders(
                  markerBuilder: (context, day, events) => events.isEmpty
                      ? null
                      : _Markers(events: events, today: today),
                ),
              ),
              if (overdue.isNotEmpty) ...[
                const _SectionTitle('Gecikmiş ödemeler'),
                for (final o in overdue) _OccurrenceTile(o, showDate: true),
              ],
              _SectionTitle(Dates.day(_selected, today)),
              if (dayItems.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: Text('Bu gün için ödeme yok.'),
                ),
              for (final o in dayItems) _OccurrenceTile(o),
            ],
          );
        },
      ),
    );
  }
}

class _MonthSummary extends StatelessWidget {
  const _MonthSummary({required this.dueThisMonth, required this.overdueCount});

  final int dueThisMonth;
  final int overdueCount;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Bu ay ödenecek', style: theme.textTheme.labelMedium),
                  Text(
                    Money.format(dueThisMonth),
                    key: const Key('due-this-month'),
                    style: theme.textTheme.titleLarge,
                  ),
                ],
              ),
            ),
            if (overdueCount > 0)
              Chip(
                avatar: Icon(
                  Icons.warning_amber,
                  color: theme.colorScheme.error,
                  size: 18,
                ),
                label: Text('$overdueCount gecikmiş'),
              ),
          ],
        ),
      ),
    );
  }
}

class _Markers extends StatelessWidget {
  const _Markers({required this.events, required this.today});

  final List<Occurrence> events;
  final DateTime today;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Positioned(
      bottom: 4,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final o in events.take(3))
            Container(
              width: 6,
              height: 6,
              margin: const EdgeInsets.symmetric(horizontal: 1),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: _statusColor(o, today, colors),
              ),
            ),
        ],
      ),
    );
  }
}

Color _statusColor(Occurrence o, DateTime today, ColorScheme colors) =>
    switch (o.status) {
      OccurrenceStatus.paid => colors.tertiary,
      OccurrenceStatus.skipped => colors.outline,
      OccurrenceStatus.pending when o.isOverdue(today) => colors.error,
      OccurrenceStatus.pending => colors.primary,
    };

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
    child: Text(text, style: Theme.of(context).textTheme.labelLarge),
  );
}

class _OccurrenceTile extends ConsumerWidget {
  const _OccurrenceTile(this.occurrence, {this.showDate = false});

  final Occurrence occurrence;
  final bool showDate;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final today = ref.watch(todayProvider);
    final colors = Theme.of(context).colorScheme;
    final o = occurrence;
    final statusText = switch (o.status) {
      OccurrenceStatus.paid =>
        o.flow == CashFlow.inflow ? 'Tahsil edildi' : 'Ödendi',
      OccurrenceStatus.skipped => 'Atlandı',
      OccurrenceStatus.pending when o.isOverdue(today) => 'Gecikmiş',
      OccurrenceStatus.pending => 'Bekliyor',
    };
    return ListTile(
      leading: CircleAvatar(
        backgroundColor: _statusColor(o, today, colors).withValues(alpha: 0.18),
        foregroundColor: _statusColor(o, today, colors),
        child: Icon(switch (o.status) {
          OccurrenceStatus.paid => Icons.check,
          OccurrenceStatus.skipped => Icons.redo,
          OccurrenceStatus.pending =>
            o.flow == CashFlow.inflow
                ? Icons.arrow_downward
                : Icons.arrow_upward,
        }),
      ),
      title: Text(o.title),
      subtitle: Text(
        showDate ? '${Dates.long(o.dueDate)} · $statusText' : statusText,
      ),
      trailing: Text(
        '${o.flow == CashFlow.inflow ? '+' : '-'}${Money.format(o.amount)}',
        style: Theme.of(context).textTheme.titleMedium?.copyWith(
          decoration: o.status == OccurrenceStatus.skipped
              ? TextDecoration.lineThrough
              : null,
        ),
      ),
      onTap: () => showOccurrenceSheet(context, o),
    );
  }
}
