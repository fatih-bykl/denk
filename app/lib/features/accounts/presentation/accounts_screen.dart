import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/money/money.dart';
import '../../../core/widgets/async_body.dart';
import '../data/accounts_repository.dart';
import '../domain/account.dart';
import 'account_form_sheet.dart';

class AccountsScreen extends ConsumerWidget {
  const AccountsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final accounts = ref.watch(accountsProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Hesaplar')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => showAccountForm(context),
        icon: const Icon(Icons.add),
        label: const Text('Hesap ekle'),
      ),
      body: AsyncBody(
        value: accounts,
        onRetry: () => ref.invalidate(accountsProvider),
        data: (all) => _AccountList(accounts: all),
      ),
    );
  }
}

class _AccountList extends StatelessWidget {
  const _AccountList({required this.accounts});

  final List<Account> accounts;

  @override
  Widget build(BuildContext context) {
    final active = accounts.where((a) => !a.isArchived).toList();
    final archived = accounts.where((a) => a.isArchived).toList();
    final total = active.fold<int>(0, (sum, a) => sum + a.balance);
    final theme = Theme.of(context);

    return ListView(
      padding: const EdgeInsets.only(bottom: 88),
      children: [
        Card(
          margin: const EdgeInsets.all(16),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Toplam bakiye', style: theme.textTheme.labelLarge),
                const SizedBox(height: 4),
                Text(
                  Money.format(total),
                  key: const Key('total-balance'),
                  style: theme.textTheme.headlineSmall?.copyWith(
                    color: total < 0 ? theme.colorScheme.error : null,
                  ),
                ),
                Text(
                  '${active.length} aktif hesap',
                  style: theme.textTheme.bodySmall,
                ),
              ],
            ),
          ),
        ),
        if (active.isEmpty)
          const Padding(
            padding: EdgeInsets.all(24),
            child: Text(
              'Aktif hesap yok. "Hesap ekle" ile bir hesap oluştur.',
              textAlign: TextAlign.center,
            ),
          ),
        for (final account in active)
          _AccountTile(account: account, activeCount: active.length),
        if (archived.isNotEmpty)
          ExpansionTile(
            title: Text('Arşivlenen hesaplar (${archived.length})'),
            children: [
              for (final account in archived)
                _AccountTile(account: account, activeCount: active.length),
            ],
          ),
      ],
    );
  }
}

class _AccountTile extends StatelessWidget {
  const _AccountTile({required this.account, required this.activeCount});

  final Account account;
  final int activeCount;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListTile(
      leading: Icon(
        account.isArchived
            ? Icons.inventory_2_outlined
            : Icons.account_balance_wallet_outlined,
      ),
      title: Text(account.name),
      trailing: Text(
        Money.format(account.balance),
        style: theme.textTheme.titleMedium?.copyWith(
          color: account.balance < 0 ? theme.colorScheme.error : null,
        ),
      ),
      enabled: true,
      textColor: account.isArchived ? theme.disabledColor : null,
      onTap: () => showAccountForm(
        context,
        account: account,
        isLastActive: !account.isArchived && activeCount == 1,
      ),
    );
  }
}
