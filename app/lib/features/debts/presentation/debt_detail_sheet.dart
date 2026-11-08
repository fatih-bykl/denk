import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/routes.dart';
import '../../../core/date/dates.dart';
import '../../../core/errors/data_failure.dart';
import '../../../core/money/money.dart';
import '../../../core/widgets/async_body.dart';
import '../../../core/widgets/money_field.dart';
import '../../accounts/data/accounts_repository.dart';
import '../../accounts/domain/account.dart';
import '../../schedule/application/schedule_providers.dart';
import '../../schedule/data/schedule_repository.dart';
import '../../transactions/data/transactions_repository.dart';
import '../../transactions/domain/transaction.dart';
import '../application/debt_service.dart';
import '../data/debts_repository.dart';
import '../domain/debt.dart';
import 'debt_form_sheet.dart';

/// Borç ayrıntısı: ilerleme, ödeme geçmişi, ödeme ekleme, kapatma.
Future<void> showDebtDetail(BuildContext context, Debt debt) =>
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _DebtDetailSheet(debtId: debt.id),
    );

class _DebtDetailSheet extends ConsumerStatefulWidget {
  const _DebtDetailSheet({required this.debtId});

  final String debtId;

  @override
  ConsumerState<_DebtDetailSheet> createState() => _DebtDetailSheetState();
}

class _DebtDetailSheetState extends ConsumerState<_DebtDetailSheet> {
  final _formKey = GlobalKey<FormState>();
  final _amount = TextEditingController();
  String? _accountId;
  late DateTime _paidOn = ref.read(todayProvider);
  bool _paying = false;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _amount.dispose();
    super.dispose();
  }

  void _invalidateAll() {
    ref
      ..invalidate(debtsProvider)
      ..invalidate(debtTransactionsProvider(widget.debtId))
      ..invalidate(monthTransactionsProvider)
      ..invalidate(accountsProvider);
    invalidateSchedule(ref);
  }

  Future<void> _run(
    Future<void> Function() action, {
    bool close = false,
  }) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await action();
      _invalidateAll();
      if (!mounted) return;
      if (close) {
        Navigator.of(context).pop();
      } else {
        setState(() => _paying = false);
      }
    } on DataFailure catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _startPayment(Debt debt) => setState(() {
    _paying = true;
    _amount.text = Money.format(
      debt.remainingAmount > 0 ? debt.remainingAmount : 0,
      symbol: false,
    );
  });

  void _pay(Debt debt) {
    if (_busy || !_formKey.currentState!.validate()) return;
    _run(
      () => ref
          .read(transactionsRepositoryProvider)
          .create(
            TransactionDraft(
              accountId: _accountId!,
              type: debt.direction.entryKind,
              amount: MoneyField.read(_amount)!,
              occurredOn: _paidOn,
              note: '${debt.title} (${debt.counterparty})',
              debtId: debt.id,
            ),
          ),
    );
  }

  Future<void> _setClosed(Debt debt, bool closed) async {
    final schedules = await ref.read(schedulesProvider.future);
    final schedule = schedules
        .where((s) => s.id == debt.scheduleId)
        .firstOrNull;
    final service = DebtService(
      debts: ref.read(debtsRepositoryProvider),
      schedules: ref.read(scheduleRepositoryProvider),
      today: ref.read(todayProvider),
    );
    await _run(() => service.setClosed(debt, schedule, closed: closed));
  }

  Future<void> _edit(Debt debt) async {
    final navigator = Navigator.of(context);
    navigator.pop();
    if (navigator.context.mounted) {
      await showDebtForm(navigator.context, debt: debt);
    }
  }

  @override
  Widget build(BuildContext context) {
    final debts = ref.watch(debtsProvider).value ?? const <Debt>[];
    final debt = debts.where((d) => d.id == widget.debtId).firstOrNull;
    if (debt == null) {
      return const SizedBox(
        height: 160,
        child: Center(child: CircularProgressIndicator()),
      );
    }
    final theme = Theme.of(context);
    final today = ref.watch(todayProvider);
    final payments =
        ref.watch(debtTransactionsProvider(debt.id)).value ??
        const <Transaction>[];
    final accounts = (ref.watch(accountsProvider).value ?? const <Account>[])
        .where((a) => !a.isArchived)
        .toList();
    _accountId ??= accounts.isEmpty ? null : accounts.first.id;
    final isPayable = debt.direction == DebtDirection.payable;
    final paidLabel = isPayable ? 'Ödenen' : 'Tahsil edilen';

    return Padding(
      padding: EdgeInsets.fromLTRB(
        24,
        0,
        24,
        24 + MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(debt.counterparty, style: theme.textTheme.titleLarge),
            Text(
              '${debt.direction.label} · ${debt.title}'
              '${debt.isClosed ? ' · Kapalı' : ''}',
              style: theme.textTheme.bodyMedium,
            ),
            const SizedBox(height: 16),
            LinearProgressIndicator(
              value: debt.progress,
              minHeight: 8,
              borderRadius: BorderRadius.circular(4),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: _Figure(
                    label: paidLabel,
                    value: Money.format(debt.paidAmount),
                  ),
                ),
                Expanded(
                  child: _Figure(
                    label: 'Kalan',
                    value: Money.format(debt.remainingAmount),
                    valueKey: const Key('debt-remaining'),
                  ),
                ),
                Expanded(
                  child: _Figure(
                    label: 'Toplam',
                    value: Money.format(debt.totalAmount),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            if (debt.hasInstallments)
              Text(
                debt.nextDueDate == null
                    ? '${debt.installmentCount} taksit · bekleyen taksit yok'
                    : '${debt.installmentCount} taksit · '
                          'sıradaki: ${Dates.long(debt.nextDueDate!)}',
                style: theme.textTheme.bodySmall,
              )
            else if (debt.dueDate != null)
              Text(
                'Vade: ${Dates.long(debt.dueDate!)}',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: !debt.isClosed && debt.dueDate!.isBefore(today)
                      ? theme.colorScheme.error
                      : null,
                ),
              ),
            if (debt.note != null) ...[
              const SizedBox(height: 4),
              Text(debt.note!, style: theme.textTheme.bodySmall),
            ],
            if (_paying) ...[
              const SizedBox(height: 16),
              Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    MoneyField(controller: _amount, label: 'Tutar'),
                    const SizedBox(height: 16),
                    DropdownButtonFormField<String>(
                      key: ValueKey(accounts.length),
                      initialValue: accounts.any((a) => a.id == _accountId)
                          ? _accountId
                          : null,
                      decoration: InputDecoration(
                        labelText: isPayable ? 'Ödenen hesap' : 'Yatan hesap',
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
                        if (d != null) {
                          setState(() => _paidOn = Dates.dateOnly(d));
                        }
                      },
                      child: InputDecorator(
                        decoration: const InputDecoration(
                          labelText: 'Tarih',
                          suffixIcon: Icon(Icons.calendar_today_outlined),
                        ),
                        child: Text(Dates.long(_paidOn)),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            if (_error != null) ...[
              const SizedBox(height: 16),
              FormErrorText(_error!),
            ],
            const SizedBox(height: 16),
            if (_paying)
              FilledButton(
                onPressed: _busy ? null : () => _pay(debt),
                child: Text(isPayable ? 'Ödemeyi kaydet' : 'Tahsilatı kaydet'),
              )
            else if (!debt.isClosed && !debt.hasInstallments)
              FilledButton.icon(
                onPressed: _busy ? null : () => _startPayment(debt),
                icon: const Icon(Icons.add),
                label: Text(isPayable ? 'Ödeme ekle' : 'Tahsilat ekle'),
              )
            else if (!debt.isClosed && debt.hasInstallments)
              FilledButton.icon(
                onPressed: () {
                  Navigator.of(context).pop();
                  context.go(Routes.schedule);
                },
                icon: const Icon(Icons.calendar_month_outlined),
                label: const Text('Taksitleri takvimde gör'),
              ),
            const SizedBox(height: 8),
            if (!debt.isClosed && debt.remainingAmount <= 0)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(
                  isPayable
                      ? 'Borcun tamamı ödendi. Kaydı kapatabilirsin.'
                      : 'Alacağın tamamı tahsil edildi. Kaydı kapatabilirsin.',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodySmall,
                ),
              ),
            OutlinedButton(
              onPressed: _busy ? null : () => _setClosed(debt, !debt.isClosed),
              child: Text(debt.isClosed ? 'Yeniden aç' : 'Kapat'),
            ),
            TextButton(
              onPressed: _busy ? null : () => _edit(debt),
              child: const Text('Düzenle'),
            ),
            if (payments.isNotEmpty) ...[
              const Divider(),
              Text(
                isPayable ? 'Ödemeler' : 'Tahsilatlar',
                style: theme.textTheme.labelLarge,
              ),
              for (final t in payments)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  title: Text(Dates.long(t.occurredOn)),
                  trailing: Text(
                    Money.format(t.amount),
                    style: t.type == debt.direction.entryKind
                        ? null
                        : TextStyle(color: theme.disabledColor),
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }
}

class _Figure extends StatelessWidget {
  const _Figure({required this.label, required this.value, this.valueKey});

  final String label;
  final String value;
  final Key? valueKey;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: theme.textTheme.labelSmall),
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text(value, key: valueKey, style: theme.textTheme.titleSmall),
        ),
      ],
    );
  }
}
