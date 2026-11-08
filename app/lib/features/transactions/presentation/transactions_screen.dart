import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/date/dates.dart';
import '../../../core/money/money.dart';
import '../../../core/widgets/async_body.dart';
import '../../accounts/data/accounts_repository.dart';
import '../../accounts/domain/account.dart';
import '../../categories/data/categories_repository.dart';
import '../../categories/domain/category.dart';
import '../../categories/presentation/category_icons.dart';
import '../data/transactions_repository.dart';
import '../domain/transaction.dart';
import 'transaction_form_sheet.dart';

class TransactionsScreen extends ConsumerStatefulWidget {
  const TransactionsScreen({super.key});

  @override
  ConsumerState<TransactionsScreen> createState() => _TransactionsScreenState();
}

class _TransactionsScreenState extends ConsumerState<TransactionsScreen> {
  late DateTime _month = Dates.monthStart(ref.read(todayProvider));
  EntryKind? _type;
  String? _accountId;
  String? _categoryId;

  List<Transaction> _filter(List<Transaction> all) => all
      .where(
        (t) =>
            (_type == null || t.type == _type) &&
            (_accountId == null || t.accountId == _accountId) &&
            (_categoryId == null || t.categoryId == _categoryId),
      )
      .toList();

  void _setType(EntryKind? type) => setState(() {
    _type = type;
    _categoryId = null;
  });

  @override
  Widget build(BuildContext context) {
    final transactions = ref.watch(monthTransactionsProvider(_month));
    final accounts = ref.watch(accountsProvider).value ?? const <Account>[];
    final categories =
        ref.watch(categoriesProvider).value ?? const <Category>[];

    return Scaffold(
      appBar: AppBar(title: const Text('İşlemler')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => showTransactionForm(context),
        icon: const Icon(Icons.add),
        label: const Text('İşlem ekle'),
      ),
      body: Column(
        children: [
          _MonthBar(
            month: _month,
            onChanged: (m) => setState(() => _month = m),
          ),
          _FilterBar(
            type: _type,
            accountId: _accountId,
            categoryId: _categoryId,
            accounts: accounts,
            categories: categories
                .where((c) => _type == null || c.kind == _type)
                .toList(),
            onType: _setType,
            onAccount: (id) => setState(() => _accountId = id),
            onCategory: (id) => setState(() => _categoryId = id),
          ),
          Expanded(
            child: AsyncBody(
              value: transactions,
              onRetry: () => ref.invalidate(monthTransactionsProvider(_month)),
              data: (all) => _TransactionList(
                transactions: _filter(all),
                isFiltered:
                    _type != null || _accountId != null || _categoryId != null,
                accounts: {for (final a in accounts) a.id: a},
                categories: {for (final c in categories) c.id: c},
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MonthBar extends StatelessWidget {
  const _MonthBar({required this.month, required this.onChanged});

  final DateTime month;
  final ValueChanged<DateTime> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        IconButton(
          tooltip: 'Önceki ay',
          icon: const Icon(Icons.chevron_left),
          onPressed: () => onChanged(Dates.addMonths(month, -1)),
        ),
        Text(
          Dates.month(month),
          key: const Key('month-label'),
          style: Theme.of(context).textTheme.titleMedium,
        ),
        IconButton(
          tooltip: 'Sonraki ay',
          icon: const Icon(Icons.chevron_right),
          onPressed: () => onChanged(Dates.addMonths(month, 1)),
        ),
      ],
    );
  }
}

class _FilterBar extends StatelessWidget {
  const _FilterBar({
    required this.type,
    required this.accountId,
    required this.categoryId,
    required this.accounts,
    required this.categories,
    required this.onType,
    required this.onAccount,
    required this.onCategory,
  });

  final EntryKind? type;
  final String? accountId;
  final String? categoryId;
  final List<Account> accounts;
  final List<Category> categories;
  final ValueChanged<EntryKind?> onType;
  final ValueChanged<String?> onAccount;
  final ValueChanged<String?> onCategory;

  @override
  Widget build(BuildContext context) {
    String nameOf<T>(
      List<T> items,
      String? id,
      String Function(T) name,
      String Function(T) idOf,
    ) {
      final match = items.where((i) => idOf(i) == id);
      return match.isEmpty ? 'Tümü' : name(match.first);
    }

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Row(
        children: [
          for (final (value, label) in [
            (null, 'Tümü'),
            (EntryKind.expense, 'Gider'),
            (EntryKind.income, 'Gelir'),
          ])
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: ChoiceChip(
                label: Text(label),
                selected: type == value,
                onSelected: (_) => onType(value),
              ),
            ),
          const SizedBox(width: 8),
          _MenuChip(
            label:
                'Hesap: ${nameOf(accounts, accountId, (a) => a.name, (a) => a.id)}',
            active: accountId != null,
            options: [for (final a in accounts) (a.id, a.name)],
            onSelected: onAccount,
          ),
          const SizedBox(width: 8),
          _MenuChip(
            label:
                'Kategori: ${nameOf(categories, categoryId, (c) => c.name, (c) => c.id)}',
            active: categoryId != null,
            options: [for (final c in categories) (c.id, c.name)],
            onSelected: onCategory,
          ),
        ],
      ),
    );
  }
}

/// Seçenekleri açılır menüde gösteren filtre çipi. "Tümü" seçimi null verir.
class _MenuChip extends StatelessWidget {
  const _MenuChip({
    required this.label,
    required this.active,
    required this.options,
    required this.onSelected,
  });

  static const _all = '__all__';

  final String label;
  final bool active;
  final List<(String, String)> options;
  final ValueChanged<String?> onSelected;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<String>(
      onSelected: (v) => onSelected(v == _all ? null : v),
      itemBuilder: (_) => [
        const PopupMenuItem(value: _all, child: Text('Tümü')),
        for (final (id, name) in options)
          PopupMenuItem(value: id, child: Text(name)),
      ],
      child: Chip(
        label: Text(label),
        avatar: const Icon(Icons.arrow_drop_down, size: 18),
        backgroundColor: active
            ? Theme.of(context).colorScheme.secondaryContainer
            : null,
      ),
    );
  }
}

class _TransactionList extends ConsumerWidget {
  const _TransactionList({
    required this.transactions,
    required this.isFiltered,
    required this.accounts,
    required this.categories,
  });

  final List<Transaction> transactions;
  final bool isFiltered;
  final Map<String, Account> accounts;
  final Map<String, Category> categories;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final today = ref.watch(todayProvider);
    final income = transactions
        .where((t) => t.type == EntryKind.income)
        .fold<int>(0, (s, t) => s + t.amount);
    final expense = transactions
        .where((t) => t.type == EntryKind.expense)
        .fold<int>(0, (s, t) => s + t.amount);

    final children = <Widget>[
      _Summary(income: income, expense: expense),
      if (transactions.isEmpty)
        Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            isFiltered
                ? 'Bu filtreye uyan işlem yok.'
                : 'Bu ay işlem yok. "İşlem ekle" ile ilk kaydını gir.',
            textAlign: TextAlign.center,
          ),
        ),
    ];
    DateTime? currentDay;
    for (final t in transactions) {
      if (t.occurredOn != currentDay) {
        currentDay = t.occurredOn;
        children.add(
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
            child: Text(
              Dates.day(t.occurredOn, today),
              style: Theme.of(context).textTheme.labelLarge,
            ),
          ),
        );
      }
      children.add(
        _TransactionTile(
          transaction: t,
          account: accounts[t.accountId],
          category: categories[t.categoryId],
        ),
      );
    }

    return ListView(
      padding: const EdgeInsets.only(bottom: 88),
      children: children,
    );
  }
}

class _Summary extends StatelessWidget {
  const _Summary({required this.income, required this.expense});

  final int income;
  final int expense;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    Widget cell(String label, int value, Key key, {Color? color}) => Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: theme.textTheme.labelMedium),
          const SizedBox(height: 2),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              Money.format(value),
              key: key,
              style: theme.textTheme.titleMedium?.copyWith(color: color),
            ),
          ),
        ],
      ),
    );
    final net = income - expense;
    return Card(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            cell('Gelir', income, const Key('sum-income')),
            cell('Gider', expense, const Key('sum-expense')),
            cell(
              'Net',
              net,
              const Key('sum-net'),
              color: net < 0 ? theme.colorScheme.error : null,
            ),
          ],
        ),
      ),
    );
  }
}

class _TransactionTile extends StatelessWidget {
  const _TransactionTile({
    required this.transaction,
    required this.account,
    required this.category,
  });

  final Transaction transaction;
  final Account? account;
  final Category? category;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final isIncome = transaction.type == EntryKind.income;
    final note = transaction.note;
    return ListTile(
      leading: CircleAvatar(
        backgroundColor: isIncome
            ? colors.primaryContainer
            : colors.surfaceContainerHighest,
        foregroundColor: isIncome
            ? colors.onPrimaryContainer
            : colors.onSurfaceVariant,
        child: Icon(CategoryIcons.of(category?.icon)),
      ),
      title: Text(category?.name ?? 'Kategorisiz'),
      subtitle: Text(
        [
          account?.name ?? '',
          if (note != null && note.isNotEmpty) note,
        ].where((s) => s.isNotEmpty).join(' · '),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: Text(
        '${isIncome ? '+' : '-'}${Money.format(transaction.amount)}',
        style: Theme.of(context).textTheme.titleMedium
            ?.copyWith(color: isIncome ? colors.primary : colors.onSurface),
      ),
      onTap: () => showTransactionForm(context, transaction: transaction),
    );
  }
}
