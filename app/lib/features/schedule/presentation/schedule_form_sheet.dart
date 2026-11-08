import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/date/dates.dart';
import '../../../core/errors/data_failure.dart';
import '../../../core/money/money.dart';
import '../../../core/recurrence/recurrence.dart';
import '../../../core/widgets/async_body.dart';
import '../../../core/widgets/money_field.dart';
import '../../categories/data/categories_repository.dart';
import '../../categories/domain/category.dart';
import '../../debts/data/debts_repository.dart';
import '../application/schedule_providers.dart';
import '../data/schedule_repository.dart';
import '../domain/payment_schedule.dart';

enum _EndMode { never, onDate, afterCount }

/// Ödeme planı ekleme (schedule == null) veya düzenleme formu.
Future<void> showScheduleForm(
  BuildContext context, {
  PaymentSchedule? schedule,
}) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  showDragHandle: true,
  builder: (_) => _ScheduleFormSheet(schedule: schedule),
);

class _ScheduleFormSheet extends ConsumerStatefulWidget {
  const _ScheduleFormSheet({this.schedule});

  final PaymentSchedule? schedule;

  @override
  ConsumerState<_ScheduleFormSheet> createState() => _ScheduleFormSheetState();
}

class _ScheduleFormSheetState extends ConsumerState<_ScheduleFormSheet> {
  final _formKey = GlobalKey<FormState>();
  late final PaymentSchedule? _s = widget.schedule;
  late final _title = TextEditingController(text: _s?.title);
  late final _amount = TextEditingController(
    text: _s == null ? '' : Money.format(_s.amount, symbol: false),
  );
  late final _interval = TextEditingController(
    text: '${_s?.intervalCount ?? 1}',
  );
  late final _count = TextEditingController(
    text: _s?.occurrenceLimit?.toString() ?? '12',
  );
  late CashFlow _flow = _s?.flow ?? CashFlow.outflow;
  late Frequency _frequency = _s?.frequency ?? Frequency.monthly;
  late DateTime _start = _s?.startDate ?? ref.read(todayProvider);
  // Varsayılan bitiş: bir yıl sonraki aynı gün (addMonths günü ayın 1'ine çeker).
  late DateTime _endDate =
      _s?.endDate ?? _oneYearLater(ref.read(todayProvider));

  static DateTime _oneYearLater(DateTime d) =>
      RecurrenceRule(frequency: Frequency.yearly, start: d).nth(1);
  late _EndMode _endMode = _s?.occurrenceLimit != null
      ? _EndMode.afterCount
      : _s?.endDate != null
      ? _EndMode.onDate
      : _EndMode.never;
  late String? _categoryId = _s?.categoryId;
  late int _remind = _s?.remindDaysBefore ?? 3;
  late bool _active = _s?.isActive ?? true;
  bool _busy = false;
  String? _error;

  bool get _isEdit => _s != null;
  bool get _repeats => _frequency != Frequency.once;

  @override
  void dispose() {
    _title.dispose();
    _amount.dispose();
    _interval.dispose();
    _count.dispose();
    super.dispose();
  }

  Future<void> _run(
    Future<void> Function(ScheduleRepository repo) action,
  ) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await action(ref.read(scheduleRepositoryProvider));
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
    final draft = ScheduleDraft(
      title: _title.text.trim(),
      flow: _flow,
      amount: MoneyField.read(_amount)!,
      frequency: _frequency,
      intervalCount: _repeats ? int.parse(_interval.text) : 1,
      startDate: _start,
      endDate: _repeats && _endMode == _EndMode.onDate ? _endDate : null,
      occurrenceLimit: _repeats && _endMode == _EndMode.afterCount
          ? int.parse(_count.text)
          : null,
      remindDaysBefore: _remind,
      categoryId: _categoryId,
      debtId: _s?.debtId,
      isActive: _active,
    );
    final today = ref.read(todayProvider);
    final existing = _s;
    _run((repo) async {
      final String id;
      if (existing != null) {
        await repo.updateSchedule(existing.id, draft);
        id = existing.id;
      } else {
        id = await repo.createSchedule(draft);
      }
      await syncSchedule(
        repo,
        PaymentSchedule.fromDraft(id, draft),
        today,
        debtTotal: await _debtTotal(draft.debtId),
      );
    });
  }

  /// Borca bağlı planda taksit tutarları borç toplamından hesaplanır.
  Future<int?> _debtTotal(String? debtId) async {
    if (debtId == null) return null;
    final debts = await ref.read(debtsProvider.future);
    return debts.where((d) => d.id == debtId).firstOrNull?.totalAmount;
  }

  Future<void> _delete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Plan silinsin mi?'),
        content: const Text(
          'Planın bekleyen dönemleri silinir. '
          'Daha önce yapılan ödemelerin işlem kayıtları kalır.',
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
    if (confirmed ?? false) await _run((repo) => repo.deleteSchedule(_s!.id));
  }

  Future<DateTime?> _pickDate(DateTime initial) => showDatePicker(
    context: context,
    initialDate: initial,
    firstDate: DateTime(2000),
    lastDate: DateTime(2100),
  );

  String? _validateInt(String? v, int min, int max) {
    final n = int.tryParse(v ?? '');
    if (n == null || n < min || n > max) {
      return '$min ile $max arası bir sayı gir.';
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final categories =
        (ref.watch(categoriesProvider).value ?? const <Category>[])
            .where(
              (c) =>
                  c.kind == _flow.entryKind &&
                  (!c.isArchived || c.id == _categoryId),
            )
            .toList();

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
                _isEdit ? 'Planı düzenle' : 'Yeni ödeme planı',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 16),
              SegmentedButton<CashFlow>(
                segments: const [
                  ButtonSegment(
                    value: CashFlow.outflow,
                    label: Text('Ödeme'),
                    icon: Icon(Icons.arrow_upward),
                  ),
                  ButtonSegment(
                    value: CashFlow.inflow,
                    label: Text('Tahsilat'),
                    icon: Icon(Icons.arrow_downward),
                  ),
                ],
                selected: {_flow},
                onSelectionChanged: (s) => setState(() {
                  _flow = s.first;
                  _categoryId = null;
                }),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _title,
                decoration: const InputDecoration(
                  labelText: 'Başlık',
                  hintText: 'ör. Kira, Elektrik, Kredi taksiti',
                ),
                maxLength: 80,
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? 'Başlık gerekli.' : null,
              ),
              const SizedBox(height: 8),
              MoneyField(controller: _amount, label: 'Tutar (her dönem)'),
              const SizedBox(height: 16),
              DropdownButtonFormField<Frequency>(
                initialValue: _frequency,
                decoration: const InputDecoration(labelText: 'Tekrar'),
                items: [
                  for (final f in Frequency.values)
                    DropdownMenuItem(value: f, child: Text(f.label)),
                ],
                onChanged: (v) => setState(() => _frequency = v!),
              ),
              if (_repeats) ...[
                const SizedBox(height: 16),
                TextFormField(
                  controller: _interval,
                  decoration: InputDecoration(
                    labelText: 'Kaç ${_frequency.unit}da bir',
                    helperText: '1 = her ${_frequency.unit}',
                  ),
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  validator: (v) => _validateInt(v, 1, 120),
                ),
              ],
              const SizedBox(height: 16),
              _DateField(
                label: _repeats ? 'İlk vade tarihi' : 'Vade tarihi',
                date: _start,
                onTap: () async {
                  final d = await _pickDate(_start);
                  if (d != null) setState(() => _start = Dates.dateOnly(d));
                },
              ),
              if (_repeats) ...[
                const SizedBox(height: 16),
                Text('Bitiş', style: Theme.of(context).textTheme.labelLarge),
                const SizedBox(height: 8),
                SegmentedButton<_EndMode>(
                  segments: const [
                    ButtonSegment(
                      value: _EndMode.never,
                      label: Text('Süresiz'),
                    ),
                    ButtonSegment(
                      value: _EndMode.afterCount,
                      label: Text('Taksit'),
                    ),
                    ButtonSegment(
                      value: _EndMode.onDate,
                      label: Text('Tarihte'),
                    ),
                  ],
                  selected: {_endMode},
                  onSelectionChanged: (s) => setState(() => _endMode = s.first),
                ),
                if (_endMode == _EndMode.afterCount) ...[
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _count,
                    decoration: const InputDecoration(
                      labelText: 'Toplam taksit / dönem sayısı',
                      helperText: 'İlk vadeden itibaren sayılır',
                    ),
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    validator: (v) => _validateInt(v, 1, 600),
                  ),
                ],
                if (_endMode == _EndMode.onDate) ...[
                  const SizedBox(height: 16),
                  _DateField(
                    label: 'Son vade tarihi',
                    date: _endDate,
                    errorText: _endDate.isBefore(_start)
                        ? 'İlk vadeden önce olamaz.'
                        : null,
                    onTap: () async {
                      final d = await _pickDate(_endDate);
                      if (d != null) {
                        setState(() => _endDate = Dates.dateOnly(d));
                      }
                    },
                  ),
                ],
              ],
              const SizedBox(height: 16),
              DropdownButtonFormField<String?>(
                // Seçenekler henüz yüklenmediyse seçili değer listede olmaz; yüklenince alan yeniden kurulur.
                key: ValueKey((_flow, categories.length)),
                initialValue: categories.any((c) => c.id == _categoryId)
                    ? _categoryId
                    : null,
                decoration: const InputDecoration(labelText: 'Kategori'),
                items: [
                  const DropdownMenuItem(child: Text('Kategorisiz')),
                  for (final c in categories)
                    DropdownMenuItem(value: c.id, child: Text(c.name)),
                ],
                onChanged: (v) => setState(() => _categoryId = v),
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<int>(
                initialValue: _remind,
                decoration: const InputDecoration(labelText: 'Hatırlatma'),
                items: [
                  for (final d in const [0, 1, 2, 3, 5, 7])
                    DropdownMenuItem(
                      value: d,
                      child: Text(d == 0 ? 'Vade günü' : '$d gün önce'),
                    ),
                ],
                onChanged: (v) => setState(() => _remind = v!),
              ),
              if (_isEdit)
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Aktif'),
                  subtitle: const Text(
                    'Pasif planın gelecekteki dönemleri takvimden kalkar.',
                  ),
                  value: _active,
                  onChanged: (v) => setState(() => _active = v),
                ),
              if (_error != null) ...[
                const SizedBox(height: 8),
                FormErrorText(_error!),
              ],
              const SizedBox(height: 16),
              FilledButton(
                onPressed:
                    _busy ||
                        (_repeats &&
                            _endMode == _EndMode.onDate &&
                            _endDate.isBefore(_start))
                    ? null
                    : _save,
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
                  label: const Text('Planı sil'),
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
    this.errorText,
  });

  final String label;
  final DateTime date;
  final VoidCallback onTap;
  final String? errorText;

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    child: InputDecorator(
      decoration: InputDecoration(
        labelText: label,
        errorText: errorText,
        suffixIcon: const Icon(Icons.calendar_today_outlined),
      ),
      child: Text(Dates.long(date)),
    ),
  );
}
