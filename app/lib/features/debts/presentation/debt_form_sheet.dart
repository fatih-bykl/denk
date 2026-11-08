import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/date/dates.dart';
import '../../../core/errors/data_failure.dart';
import '../../../core/money/money.dart';
import '../../../core/widgets/async_body.dart';
import '../../../core/widgets/money_field.dart';
import '../../schedule/application/schedule_providers.dart';
import '../../schedule/data/schedule_repository.dart';
import '../../schedule/domain/payment_schedule.dart';
import '../application/debt_service.dart';
import '../data/debts_repository.dart';
import '../domain/debt.dart';

/// Borç/alacak ekleme (debt == null) veya düzenleme formu.
Future<void> showDebtForm(
  BuildContext context, {
  Debt? debt,
  DebtDirection direction = DebtDirection.payable,
}) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  showDragHandle: true,
  builder: (_) => _DebtFormSheet(debt: debt, initialDirection: direction),
);

class _DebtFormSheet extends ConsumerStatefulWidget {
  const _DebtFormSheet({this.debt, required this.initialDirection});

  final Debt? debt;
  final DebtDirection initialDirection;

  @override
  ConsumerState<_DebtFormSheet> createState() => _DebtFormSheetState();
}

class _DebtFormSheetState extends ConsumerState<_DebtFormSheet> {
  final _formKey = GlobalKey<FormState>();
  late final Debt? _d = widget.debt;
  late final _counterparty = TextEditingController(text: _d?.counterparty);
  late final _title = TextEditingController(text: _d?.title);
  late final _total = TextEditingController(
    text: _d == null ? '' : Money.format(_d.totalAmount, symbol: false),
  );
  late final _count = TextEditingController(
    text: '${_d?.installmentCount ?? 12}',
  );
  late final _note = TextEditingController(text: _d?.note);
  late DebtDirection _direction = _d?.direction ?? widget.initialDirection;
  late bool _installments = _d?.hasInstallments ?? false;
  late DateTime _firstInstallment = Dates.addMonthsKeepDay(
    ref.read(todayProvider),
    1,
  );
  late DateTime? _dueDate = _d?.dueDate;
  PaymentSchedule? _schedule;
  bool _busy = false;
  String? _error;

  bool get _isEdit => _d != null;

  @override
  void initState() {
    super.initState();
    // Taksit önizlemesi tutar yazıldıkça güncellensin.
    _total.addListener(_refresh);
    _loadSchedule();
  }

  /// Düzenlemede mevcut taksit planının ilk vade tarihini forma getirir.
  Future<void> _loadSchedule() async {
    final scheduleId = _d?.scheduleId;
    if (scheduleId == null) return;
    final schedules = await ref.read(schedulesProvider.future);
    final s = schedules.where((s) => s.id == scheduleId).firstOrNull;
    if (s != null && mounted) {
      setState(() {
        _schedule = s;
        _firstInstallment = s.startDate;
      });
    }
  }

  void _refresh() => setState(() {});

  @override
  void dispose() {
    _total.removeListener(_refresh);
    _counterparty.dispose();
    _title.dispose();
    _total.dispose();
    _count.dispose();
    _note.dispose();
    super.dispose();
  }

  Future<void> _run(Future<void> Function() action) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await action();
      ref.invalidate(debtsProvider);
      invalidateSchedule(ref);
      if (mounted) Navigator.of(context).pop();
    } on DataFailure catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _save() {
    if (_busy || !_formKey.currentState!.validate()) return;
    final count = _installments ? int.parse(_count.text) : null;
    final draft = DebtDraft(
      direction: _direction,
      counterparty: _counterparty.text.trim(),
      title: _title.text.trim(),
      totalAmount: MoneyField.read(_total)!,
      installmentCount: count,
      dueDate: _installments ? null : _dueDate,
      note: _note.text,
    );
    final service = DebtService(
      debts: ref.read(debtsRepositoryProvider),
      schedules: ref.read(scheduleRepositoryProvider),
      today: ref.read(todayProvider),
    );
    _run(
      () => service.save(
        existing: _d,
        existingSchedule: _schedule,
        draft: draft,
        firstInstallment: _installments ? _firstInstallment : null,
      ),
    );
  }

  Future<void> _delete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('${_direction.label} silinsin mi?'),
        content: const Text(
          'Kayıt ve bekleyen taksitleri silinir. '
          'Yapılmış ödemelerin işlem kayıtları kalır.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Vazgeç'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Sil'),
          ),
        ],
      ),
    );
    if (confirmed ?? false) {
      await _run(() => ref.read(debtsRepositoryProvider).delete(_d!.id));
    }
  }

  Future<DateTime?> _pickDate(DateTime initial) => showDatePicker(
    context: context,
    initialDate: initial,
    firstDate: DateTime(2000),
    lastDate: DateTime(2100),
  );

  @override
  Widget build(BuildContext context) {
    final total = Money.parse(_total.text.trim());
    final count = int.tryParse(_count.text);
    final preview = _installments && total != null && count != null && count > 0
        ? splitInstallments(total, count)
        : null;

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
              Text(
                _isEdit ? 'Kaydı düzenle' : 'Yeni borç / alacak',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 16),
              SegmentedButton<DebtDirection>(
                segments: const [
                  ButtonSegment(
                    value: DebtDirection.payable,
                    label: Text('Borcum'),
                  ),
                  ButtonSegment(
                    value: DebtDirection.receivable,
                    label: Text('Alacağım'),
                  ),
                ],
                selected: {_direction},
                onSelectionChanged: (s) => setState(() => _direction = s.first),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _counterparty,
                decoration: InputDecoration(
                  labelText: _direction == DebtDirection.payable
                      ? 'Kime borçlusun?'
                      : 'Kimden alacaklısın?',
                  hintText: 'Kişi veya kurum (ör. Ali, X Bankası)',
                ),
                maxLength: 80,
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? 'Bu alan gerekli.' : null,
              ),
              const SizedBox(height: 8),
              TextFormField(
                controller: _title,
                decoration: const InputDecoration(
                  labelText: 'Açıklama',
                  hintText: 'ör. İhtiyaç kredisi, Elden borç',
                ),
                maxLength: 80,
                validator: (v) => (v == null || v.trim().isEmpty)
                    ? 'Açıklama gerekli.'
                    : null,
              ),
              const SizedBox(height: 8),
              MoneyField(controller: _total, label: 'Toplam tutar'),
              const SizedBox(height: 8),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Taksitli'),
                subtitle: const Text('Aylık taksitler takvime eklenir'),
                value: _installments,
                onChanged: (v) => setState(() => _installments = v),
              ),
              if (_installments) ...[
                TextFormField(
                  controller: _count,
                  decoration: const InputDecoration(labelText: 'Taksit sayısı'),
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  onChanged: (_) => setState(() {}),
                  validator: (v) {
                    final n = int.tryParse(v ?? '');
                    return (n == null || n < 1 || n > 600)
                        ? '1 ile 600 arası bir sayı gir.'
                        : null;
                  },
                ),
                const SizedBox(height: 16),
                _DateField(
                  label: 'İlk taksit tarihi',
                  date: _firstInstallment,
                  onTap: () async {
                    final d = await _pickDate(_firstInstallment);
                    if (d != null) {
                      setState(() => _firstInstallment = Dates.dateOnly(d));
                    }
                  },
                ),
                if (preview != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    preview.first == preview.last
                        ? '$count × ${Money.format(preview.first)}'
                        : '${count! - 1} × ${Money.format(preview.first)} + '
                              'son taksit ${Money.format(preview.last)}',
                    key: const Key('installment-preview'),
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ] else ...[
                _DateField(
                  label: 'Vade tarihi (isteğe bağlı)',
                  date: _dueDate,
                  onTap: () async {
                    final d = await _pickDate(
                      _dueDate ?? ref.read(todayProvider),
                    );
                    if (d != null) setState(() => _dueDate = Dates.dateOnly(d));
                  },
                  onClear: _dueDate == null
                      ? null
                      : () => setState(() => _dueDate = null),
                ),
              ],
              const SizedBox(height: 16),
              TextFormField(
                controller: _note,
                decoration: const InputDecoration(
                  labelText: 'Not (isteğe bağlı)',
                ),
                maxLength: 500,
                maxLines: 2,
                minLines: 1,
              ),
              if (_error != null) ...[
                const SizedBox(height: 8),
                FormErrorText(_error!),
              ],
              const SizedBox(height: 16),
              FilledButton(
                onPressed: _busy ? null : _save,
                child: const Text('Kaydet'),
              ),
              if (_isEdit) ...[
                const SizedBox(height: 8),
                TextButton.icon(
                  onPressed: _busy ? null : _delete,
                  style: TextButton.styleFrom(
                    foregroundColor: Theme.of(context).colorScheme.error,
                  ),
                  icon: const Icon(Icons.delete_outline),
                  label: const Text('Kaydı sil'),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _DateField extends StatelessWidget {
  const _DateField({
    required this.label,
    required this.date,
    required this.onTap,
    this.onClear,
  });

  final String label;
  final DateTime? date;
  final VoidCallback onTap;
  final VoidCallback? onClear;

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    child: InputDecorator(
      decoration: InputDecoration(
        labelText: label,
        suffixIcon: onClear == null
            ? const Icon(Icons.calendar_today_outlined)
            : IconButton(
                tooltip: 'Tarihi kaldır',
                icon: const Icon(Icons.clear),
                onPressed: onClear,
              ),
      ),
      child: Text(date == null ? 'Yok' : Dates.long(date!)),
    ),
  );
}
