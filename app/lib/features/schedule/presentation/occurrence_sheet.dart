import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/date/dates.dart';
import '../../../core/errors/data_failure.dart';
import '../../../core/money/money.dart';
import '../../../core/widgets/async_body.dart';
import '../../../core/widgets/money_field.dart';
import '../../accounts/data/accounts_repository.dart';
import '../../accounts/domain/account.dart';
import '../../transactions/data/transactions_repository.dart';
import '../application/schedule_providers.dart';
import '../data/schedule_repository.dart';
import '../domain/occurrence.dart';
import '../domain/payment_schedule.dart';
import 'schedule_form_sheet.dart';

/// Bir dönemin ayrıntısı: öde, atla, geri al, planı düzenle.
Future<void> showOccurrenceSheet(BuildContext context, Occurrence occurrence) =>
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _OccurrenceSheet(occurrence: occurrence),
    );

class _OccurrenceSheet extends ConsumerStatefulWidget {
  const _OccurrenceSheet({required this.occurrence});

  final Occurrence occurrence;

  @override
  ConsumerState<_OccurrenceSheet> createState() => _OccurrenceSheetState();
}

class _OccurrenceSheetState extends ConsumerState<_OccurrenceSheet> {
  final _formKey = GlobalKey<FormState>();
  late final _amount = TextEditingController(
    text: Money.format(widget.occurrence.amount, symbol: false),
  );
  late DateTime _paidOn = ref.read(todayProvider);
  String? _accountId;
  bool _busy = false;
  String? _error;

  Occurrence get _o => widget.occurrence;
  bool get _isInflow => _o.flow == CashFlow.inflow;

  @override
  void dispose() {
    _amount.dispose();
    super.dispose();
  }

  Future<void> _run(
    Future<void> Function(ScheduleRepository repo) action, {
    bool touchesTransactions = false,
  }) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await action(ref.read(scheduleRepositoryProvider));
      invalidateSchedule(ref);
      if (touchesTransactions) {
        ref
          ..invalidate(monthTransactionsProvider)
          ..invalidate(accountsProvider);
      }
      if (mounted) Navigator.of(context).pop();
    } on DataFailure catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _pay() {
    if (_busy || !_formKey.currentState!.validate()) return;
    _run(
      (repo) => repo.pay(
        _o.id,
        accountId: _accountId!,
        amount: MoneyField.read(_amount)!,
        paidOn: _paidOn,
      ),
      touchesTransactions: true,
    );
  }

  /// Ödemeyi geri almak, oluşan işlemi silmektir; veritabanı dönemi yeniden açar.
  void _undoPayment() => _run(
    (_) => ref.read(transactionsRepositoryProvider).delete(_o.transactionId!),
    touchesTransactions: true,
  );

  Future<void> _editPlan() async {
    // Bu sayfa kapanınca kendi context'i geçersiz olur; formu navigator'ın context'iyle aç.
    final navigator = Navigator.of(context);
    final schedules = await ref.read(schedulesProvider.future);
    final plan = schedules.where((s) => s.id == _o.scheduleId).firstOrNull;
    if (!mounted || plan == null) return;
    navigator.pop();
    if (navigator.context.mounted) {
      await showScheduleForm(navigator.context, schedule: plan);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final today = ref.watch(todayProvider);
    final accounts = (ref.watch(accountsProvider).value ?? const <Account>[])
        .where((a) => !a.isArchived)
        .toList();
    _accountId ??= accounts.isEmpty ? null : accounts.first.id;

    final status = switch (_o.status) {
      OccurrenceStatus.paid => _isInflow ? 'Tahsil edildi' : 'Ödendi',
      OccurrenceStatus.skipped => 'Atlandı',
      OccurrenceStatus.pending when _o.isOverdue(today) => 'Gecikmiş',
      OccurrenceStatus.pending => 'Bekliyor',
    };

    return Padding(
      padding: EdgeInsets.fromLTRB(
        24,
        0,
        24,
        24 + MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(_o.title, style: theme.textTheme.titleLarge),
              const SizedBox(height: 4),
              Text(
                '${Dates.long(_o.dueDate)} · ${Money.format(_o.amount)} · $status',
                style: theme.textTheme.bodyMedium,
              ),
              const SizedBox(height: 16),
              if (_o.isPending) ...[
                MoneyField(controller: _amount, label: 'Tutar'),
                const SizedBox(height: 16),
                DropdownButtonFormField<String>(
                  key: ValueKey(accounts.length),
                  initialValue: _accountId,
                  decoration: InputDecoration(
                    labelText: _isInflow ? 'Yatan hesap' : 'Ödenen hesap',
                    helperText: accounts.isEmpty
                        ? 'Önce Ayarlar → Hesaplar bölümünden bir hesap ekle.'
                        : null,
                  ),
                  items: [
                    for (final a in accounts)
                      DropdownMenuItem(value: a.id, child: Text(a.name)),
                  ],
                  onChanged: (v) => setState(() => _accountId = v),
                  validator: (v) => v == null ? 'Hesap seç.' : null,
                ),
                const SizedBox(height: 16),
                InkWell(
                  onTap: () async {
                    final d = await showDatePicker(
                      context: context,
                      initialDate: _paidOn,
                      firstDate: DateTime(2000),
                      lastDate: DateTime(2100),
                    );
                    if (d != null) setState(() => _paidOn = Dates.dateOnly(d));
                  },
                  child: InputDecorator(
                    decoration: InputDecoration(
                      labelText: _isInflow ? 'Tahsil tarihi' : 'Ödeme tarihi',
                      suffixIcon: const Icon(Icons.calendar_today_outlined),
                    ),
                    child: Text(Dates.long(_paidOn)),
                  ),
                ),
              ],
              if (_error != null) ...[
                const SizedBox(height: 16),
                FormErrorText(_error!),
              ],
              const SizedBox(height: 16),
              ...switch (_o.status) {
                OccurrenceStatus.pending => [
                  FilledButton.icon(
                    onPressed: _busy ? null : _pay,
                    icon: const Icon(Icons.check),
                    label: Text(
                      _isInflow
                          ? 'Tahsil edildi olarak kaydet'
                          : 'Ödendi olarak kaydet',
                    ),
                  ),
                  const SizedBox(height: 8),
                  OutlinedButton(
                    onPressed: _busy
                        ? null
                        : () => _run(
                            (repo) => repo.setSkipped(_o.id, skipped: true),
                          ),
                    child: const Text('Bu dönemi atla'),
                  ),
                ],
                OccurrenceStatus.paid => [
                  OutlinedButton.icon(
                    onPressed: _busy || _o.transactionId == null
                        ? null
                        : _undoPayment,
                    icon: const Icon(Icons.undo),
                    label: const Text('Ödemeyi geri al'),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Geri alınca ödemeden oluşan işlem kaydı silinir.',
                    style: theme.textTheme.bodySmall,
                    textAlign: TextAlign.center,
                  ),
                ],
                OccurrenceStatus.skipped => [
                  OutlinedButton.icon(
                    onPressed: _busy
                        ? null
                        : () => _run(
                            (repo) => repo.setSkipped(_o.id, skipped: false),
                          ),
                    icon: const Icon(Icons.undo),
                    label: const Text('Atlamayı geri al'),
                  ),
                ],
              },
              const SizedBox(height: 8),
              TextButton(
                onPressed: _busy ? null : _editPlan,
                child: const Text('Planı düzenle'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
