import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/errors/data_failure.dart';
import '../../../core/money/money.dart';
import '../../../core/widgets/async_body.dart';
import '../../../core/widgets/money_field.dart';
import '../data/accounts_repository.dart';
import '../domain/account.dart';

/// Hesap ekleme (account == null) veya düzenleme formu.
Future<void> showAccountForm(
  BuildContext context, {
  Account? account,
  bool isLastActive = false,
}) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  showDragHandle: true,
  builder: (_) =>
      _AccountFormSheet(account: account, isLastActive: isLastActive),
);

class _AccountFormSheet extends ConsumerStatefulWidget {
  const _AccountFormSheet({this.account, required this.isLastActive});

  final Account? account;
  final bool isLastActive;

  @override
  ConsumerState<_AccountFormSheet> createState() => _AccountFormSheetState();
}

class _AccountFormSheetState extends ConsumerState<_AccountFormSheet> {
  final _formKey = GlobalKey<FormState>();
  late final _name = TextEditingController(text: widget.account?.name);
  late final _opening = TextEditingController(
    text: widget.account == null
        ? ''
        : Money.format(widget.account!.openingBalance, symbol: false),
  );
  bool _busy = false;
  String? _error;

  bool get _isEdit => widget.account != null;

  @override
  void dispose() {
    _name.dispose();
    _opening.dispose();
    super.dispose();
  }

  Future<void> _run(
    Future<void> Function(AccountsRepository repo) action,
  ) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await action(ref.read(accountsRepositoryProvider));
      ref.invalidate(accountsProvider);
      if (mounted) Navigator.of(context).pop();
    } on DataFailure catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _save() {
    if (_busy || !_formKey.currentState!.validate()) return;
    final name = _name.text.trim();
    final opening = MoneyField.read(_opening, allowNegative: true)!;
    _run(
      (repo) => _isEdit
          ? repo.update(widget.account!.id, name: name, openingBalance: opening)
          : repo.create(name: name, openingBalance: opening),
    );
  }

  void _toggleArchive() {
    final account = widget.account!;
    if (!account.isArchived && widget.isLastActive) {
      setState(() => _error = 'En az bir aktif hesap olmalı.');
      return;
    }
    _run((repo) => repo.setArchived(account.id, archived: !account.isArchived));
  }

  @override
  Widget build(BuildContext context) {
    final account = widget.account;
    return Padding(
      padding: EdgeInsets.fromLTRB(
        24,
        0,
        24,
        24 + MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              _isEdit ? 'Hesabı düzenle' : 'Yeni hesap',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _name,
              autofocus: !_isEdit,
              decoration: const InputDecoration(
                labelText: 'Hesap adı',
                hintText: 'ör. Nakit, Banka, Kredi kartı',
              ),
              maxLength: 60,
              textInputAction: TextInputAction.next,
              validator: (v) =>
                  (v == null || v.trim().isEmpty) ? 'Hesap adı gerekli.' : null,
            ),
            const SizedBox(height: 8),
            MoneyField(
              controller: _opening,
              label: 'Açılış bakiyesi',
              allowNegative: true,
              required: false,
              helperText: 'Hesaptaki mevcut para. Borçlu hesapta eksi gir.',
            ),
            if (_error != null) ...[
              const SizedBox(height: 16),
              FormErrorText(_error!),
            ],
            const SizedBox(height: 24),
            FilledButton(
              onPressed: _busy ? null : _save,
              child: const Text('Kaydet'),
            ),
            if (account != null) ...[
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: _busy ? null : _toggleArchive,
                icon: Icon(
                  account.isArchived
                      ? Icons.unarchive_outlined
                      : Icons.archive_outlined,
                ),
                label: Text(account.isArchived ? 'Arşivden çıkar' : 'Arşivle'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
