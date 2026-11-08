import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/date/dates.dart';
import '../../../core/errors/data_failure.dart';
import '../../../core/money/money.dart';
import '../../../core/widgets/async_body.dart';
import '../../../core/widgets/money_field.dart';
import '../../accounts/data/accounts_repository.dart';
import '../../accounts/domain/account.dart';
import '../../categories/data/categories_repository.dart';
import '../../categories/domain/category.dart';
import '../../schedule/application/schedule_providers.dart';
import '../data/transactions_repository.dart';
import '../domain/transaction.dart';

/// İşlem ekleme (transaction == null) veya düzenleme formu.
Future<void> showTransactionForm(
  BuildContext context, {
  Transaction? transaction,
}) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  showDragHandle: true,
  builder: (_) => _TransactionFormSheet(transaction: transaction),
);

class _TransactionFormSheet extends ConsumerStatefulWidget {
  const _TransactionFormSheet({this.transaction});

  final Transaction? transaction;

  @override
  ConsumerState<_TransactionFormSheet> createState() =>
      _TransactionFormSheetState();
}

class _TransactionFormSheetState extends ConsumerState<_TransactionFormSheet> {
  final _formKey = GlobalKey<FormState>();
  late final _amount = TextEditingController(
    text: widget.transaction == null
        ? ''
        : Money.format(widget.transaction!.amount, symbol: false),
  );
  late final _note = TextEditingController(text: widget.transaction?.note);
  late EntryKind _type = widget.transaction?.type ?? EntryKind.expense;
  late String? _accountId = widget.transaction?.accountId;
  late String? _categoryId = widget.transaction?.categoryId;
  late DateTime _date =
      widget.transaction?.occurredOn ?? ref.read(todayProvider);
  bool _busy = false;
  String? _error;

  bool get _isEdit => widget.transaction != null;

  @override
  void dispose() {
    _amount.dispose();
    _note.dispose();
    super.dispose();
  }

  Future<void> _run(
    Future<void> Function(TransactionsRepository repo) action,
  ) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await action(ref.read(transactionsRepositoryProvider));
      // İşlem listesi ve hesap bakiyeleri değişti. Ödeme işlemi silindiyse
      // dönemi yeniden açılır; takvim, borçlar ve hatırlatmalar da yenilenir.
      ref
        ..invalidate(monthTransactionsProvider)
        ..invalidate(accountsProvider);
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
    final draft = TransactionDraft(
      accountId: _accountId!,
      categoryId: _categoryId,
      type: _type,
      amount: MoneyField.read(_amount)!,
      occurredOn: _date,
      note: _note.text,
      // Düzenleme borç bağını koparmasın.
      debtId: widget.transaction?.debtId,
    );
    _run(
      (repo) => _isEdit
          ? repo.update(widget.transaction!.id, draft)
          : repo.create(draft),
    );
  }

  Future<void> _delete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('İşlem silinsin mi?'),
        content: const Text('Bu işlem kalıcı olarak silinir.'),
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
      await _run((repo) => repo.delete(widget.transaction!.id));
    }
  }

  Future<void> _pickDate() async {
    final today = ref.read(todayProvider);
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(2000),
      lastDate: DateTime(today.year + 5, 12, 31),
    );
    if (picked != null) setState(() => _date = Dates.dateOnly(picked));
  }

  void _setType(EntryKind type) {
    setState(() {
      _type = type;
      // Kategori türü işlem türüyle aynı olmalı.
      final categories = ref.read(categoriesProvider).value ?? const [];
      final current = categories.where((c) => c.id == _categoryId);
      if (current.isNotEmpty && current.first.kind != type) _categoryId = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final accounts = ref.watch(accountsProvider).value ?? const <Account>[];
    final categories =
        ref.watch(categoriesProvider).value ?? const <Category>[];
    // Arşivlenmiş kayıtlar yalnızca bu işlemde zaten seçiliyse gösterilir.
    final accountOptions = accounts
        .where((a) => !a.isArchived || a.id == _accountId)
        .toList();
    final categoryOptions = categories
        .where((c) => c.kind == _type && (!c.isArchived || c.id == _categoryId))
        .toList();
    _accountId ??= accountOptions.isEmpty ? null : accountOptions.first.id;

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
                _isEdit ? 'İşlemi düzenle' : 'Yeni işlem',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 16),
              SegmentedButton<EntryKind>(
                segments: const [
                  ButtonSegment(
                    value: EntryKind.expense,
                    label: Text('Gider'),
                    icon: Icon(Icons.arrow_upward),
                  ),
                  ButtonSegment(
                    value: EntryKind.income,
                    label: Text('Gelir'),
                    icon: Icon(Icons.arrow_downward),
                  ),
                ],
                selected: {_type},
                onSelectionChanged: (s) => _setType(s.first),
              ),
              const SizedBox(height: 16),
              MoneyField(controller: _amount, label: 'Tutar'),
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                // Hesaplar form açıldıktan sonra yüklenirse varsayılan seçim de gelsin.
                key: ValueKey(accountOptions.length),
                initialValue: accountOptions.any((a) => a.id == _accountId)
                    ? _accountId
                    : null,
                decoration: InputDecoration(
                  labelText: 'Hesap',
                  helperText: accountOptions.isEmpty
                      ? 'Önce Ayarlar → Hesaplar bölümünden bir hesap ekle.'
                      : null,
                ),
                items: [
                  for (final a in accountOptions)
                    DropdownMenuItem(value: a.id, child: Text(a.name)),
                ],
                onChanged: (v) => setState(() => _accountId = v),
                validator: (v) => v == null ? 'Hesap seç.' : null,
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<String?>(
                // Tür değişince seçenekler değiştiği için alan yeniden kurulur.
                // Seçenekler henüz yüklenmediyse seçili değer listede olmaz; yüklenince alan yeniden kurulur.
                key: ValueKey((_type, categoryOptions.length)),
                initialValue: categoryOptions.any((c) => c.id == _categoryId)
                    ? _categoryId
                    : null,
                decoration: const InputDecoration(labelText: 'Kategori'),
                items: [
                  const DropdownMenuItem(child: Text('Kategorisiz')),
                  for (final c in categoryOptions)
                    DropdownMenuItem(value: c.id, child: Text(c.name)),
                ],
                onChanged: (v) => setState(() => _categoryId = v),
              ),
              const SizedBox(height: 16),
              InkWell(
                onTap: _pickDate,
                child: InputDecorator(
                  decoration: const InputDecoration(
                    labelText: 'Tarih',
                    suffixIcon: Icon(Icons.calendar_today_outlined),
                  ),
                  child: Text(Dates.long(_date)),
                ),
              ),
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
                  label: const Text('İşlemi sil'),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
