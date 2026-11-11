import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show ProviderListenable;
import 'package:go_router/go_router.dart';

import '../../../app/routes.dart';
import '../../../core/date/dates.dart';
import '../../../core/money/money.dart';
import '../../accounts/data/accounts_repository.dart';
import '../../accounts/domain/account.dart';
import '../../schedule/application/schedule_providers.dart';
import '../../schedule/domain/occurrence.dart';
import '../../schedule/domain/payment_schedule.dart';
import '../../schedule/presentation/occurrence_sheet.dart';
import '../../../services/notifications/reminder.dart';
import '../../../services/notifications/reminder_sync.dart';
import '../application/category_breakdown.dart';
import '../application/dashboard_providers.dart';
import 'cash_flow_chart.dart';
import 'month_overview.dart';

class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(title: const Text('Özet')),
      body: RefreshIndicator(
        onRefresh: () async {
          ref
            ..invalidate(accountsProvider)
            ..invalidate(duePaymentsProvider)
            ..invalidate(upcomingOccurrencesProvider)
            ..invalidate(cashFlowProvider)
            ..invalidate(categoryBreakdownProvider)
            ..invalidate(monthComparisonProvider)
            ..invalidate(remindableOccurrencesProvider);
          invalidateSchedule(ref);
        },
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          children: const [
            _DueSoonBanner(),
            _BalanceCard(),
            SizedBox(height: 12),
            MonthOverviewCard(),
            CategoryListCard(),
            SizedBox(height: 12),
            _DueCard(),
            SizedBox(height: 12),
            _UpcomingCard(),
            SizedBox(height: 12),
            _CashFlowCard(),
          ],
        ),
      ),
    );
  }
}

/// Kart içinde küçük bir yükleniyor/hata/veri gösterimi.
class _Section<T> extends ConsumerWidget {
  const _Section({required this.provider, required this.builder});

  final ProviderListenable<AsyncValue<T>> provider;
  final Widget Function(BuildContext context, T data) builder;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final value = ref.watch(provider);
    return switch (value) {
      AsyncData(:final value) => builder(context, value),
      AsyncError() => Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Text(
          'Yüklenemedi. Aşağı çekerek yenile.',
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ),
      _ => const Padding(
        padding: EdgeInsets.symmetric(vertical: 16),
        child: Center(child: CircularProgressIndicator()),
      ),
    };
  }
}

class _BalanceCard extends StatelessWidget {
  const _BalanceCard();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => context.go(Routes.accounts),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: _Section<List<Account>>(
            provider: accountsProvider,
            builder: (context, accounts) {
              final active = accounts.where((a) => !a.isArchived).toList();
              final total = active.fold<int>(0, (s, a) => s + a.balance);
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Toplam bakiye', style: theme.textTheme.labelLarge),
                  const SizedBox(height: 4),
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Text(
                      Money.format(total),
                      key: const Key('dash-balance'),
                      style: theme.textTheme.displaySmall?.copyWith(
                        fontWeight: FontWeight.w600,
                        color: total < 0 ? theme.colorScheme.error : null,
                      ),
                    ),
                  ),
                  Text(
                    '${active.length} hesap',
                    style: theme.textTheme.bodySmall,
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

class _DueCard extends StatelessWidget {
  const _DueCard();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => context.go(Routes.schedule),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: _Section<DuePayments>(
            provider: duePaymentsProvider,
            builder: (context, due) => Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Bu ay ödenecek',
                        style: theme.textTheme.labelMedium,
                      ),
                      const SizedBox(height: 2),
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerLeft,
                        child: Text(
                          Money.format(due.thisMonth),
                          key: const Key('dash-due'),
                          style: theme.textTheme.titleLarge,
                        ),
                      ),
                    ],
                  ),
                ),
                if (due.overdueCount > 0)
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(
                              Icons.warning_amber,
                              size: 16,
                              color: theme.colorScheme.error,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              'Gecikmiş (${due.overdueCount})',
                              style: theme.textTheme.labelMedium,
                            ),
                          ],
                        ),
                        const SizedBox(height: 2),
                        FittedBox(
                          fit: BoxFit.scaleDown,
                          alignment: Alignment.centerLeft,
                          child: Text(
                            Money.format(due.overdue),
                            key: const Key('dash-overdue'),
                            style: theme.textTheme.titleLarge?.copyWith(
                              color: theme.colorScheme.error,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _UpcomingCard extends ConsumerWidget {
  const _UpcomingCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final today = ref.watch(todayProvider);
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Yaklaşan ödemeler',
                    style: theme.textTheme.titleMedium,
                  ),
                ),
                TextButton(
                  onPressed: () => context.go(Routes.schedule),
                  child: const Text('Takvim'),
                ),
              ],
            ),
            _Section<List<Occurrence>>(
              provider: upcomingOccurrencesProvider,
              builder: (context, items) => items.isEmpty
                  ? Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Text(
                        'Yaklaşan ödeme yok.',
                        style: theme.textTheme.bodyMedium,
                      ),
                    )
                  : Column(
                      children: [
                        for (final o in items)
                          _UpcomingTile(occurrence: o, today: today),
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _UpcomingTile extends StatelessWidget {
  const _UpcomingTile({required this.occurrence, required this.today});

  final Occurrence occurrence;
  final DateTime today;

  @override
  Widget build(BuildContext context) {
    final o = occurrence;
    final days = o.dueDate.difference(today).inDays;
    final when = switch (days) {
      0 => 'Bugün',
      1 => 'Yarın',
      _ => '${Dates.long(o.dueDate)} · $days gün sonra',
    };
    final isInflow = o.flow == CashFlow.inflow;
    return ListTile(
      contentPadding: EdgeInsets.zero,
      dense: true,
      leading: Icon(isInflow ? Icons.arrow_downward : Icons.arrow_upward),
      title: Text(o.title),
      subtitle: Text(when),
      trailing: Text(
        '${isInflow ? '+' : '-'}${Money.format(o.amount)}',
        style: Theme.of(context).textTheme.titleSmall,
      ),
      onTap: () => showOccurrenceSheet(context, o),
    );
  }
}

class _CashFlowCard extends StatelessWidget {
  const _CashFlowCard();

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Nakit akışı · son $cashFlowMonths ay',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 12),
            _Section<List<MonthFlow>>(
              provider: cashFlowProvider,
              builder: (context, months) => CashFlowChart(months: months),
            ),
          ],
        ),
      ),
    );
  }
}

/// Hatırlatma zamanı gelmiş ödemeler için uygulama içi uyarı. Bildirimin
/// olmadığı web'de hatırlatmanın kendisi budur; Android'de de görünür.
class _DueSoonBanner extends ConsumerWidget {
  const _DueSoonBanner();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final items = ref.watch(dueSoonProvider).value ?? const [];
    if (items.isEmpty) return const SizedBox.shrink();
    final theme = Theme.of(context);
    final today = ref.watch(todayProvider);
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Card(
        key: const Key('due-soon'),
        margin: EdgeInsets.zero,
        color: theme.colorScheme.tertiaryContainer,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    Icons.notifications_active_outlined,
                    size: 20,
                    color: theme.colorScheme.onTertiaryContainer,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'Yaklaşan ödemeler',
                    style: theme.textTheme.titleSmall?.copyWith(
                      color: theme.colorScheme.onTertiaryContainer,
                    ),
                  ),
                ],
              ),
              for (final item in items)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  textColor: theme.colorScheme.onTertiaryContainer,
                  title: Text(item.occurrence.title),
                  subtitle: Text(
                    '${_capitalize(relativeDay(today, item.occurrence.dueDate))} · '
                    '${Dates.long(item.occurrence.dueDate)}',
                  ),
                  trailing: Text(
                    '${item.occurrence.flow == CashFlow.inflow ? '+' : '-'}'
                    '${Money.format(item.occurrence.amount)}',
                    style: theme.textTheme.titleSmall?.copyWith(
                      color: theme.colorScheme.onTertiaryContainer,
                    ),
                  ),
                  onTap: () => showOccurrenceSheet(context, item.occurrence),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

String _capitalize(String s) =>
    s.isEmpty ? s : '${s[0].toUpperCase()}${s.substring(1)}';
