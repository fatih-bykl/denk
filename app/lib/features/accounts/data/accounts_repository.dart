import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/data_generation.dart';

import '../../../core/errors/data_failure.dart';
import '../../../core/database/app_database.dart';
import '../domain/account.dart';

/// Tüm metotlar hata durumunda [DataFailure] fırlatır.
abstract interface class AccountsRepository {
  Future<List<Account>> fetchAll();
  Future<void> create({required String name, required int openingBalance});
  Future<void> update(
    String id, {
    required String name,
    required int openingBalance,
  });
  Future<void> setArchived(String id, {required bool archived});
}

final accountsRepositoryProvider = Provider<AccountsRepository>(
  (ref) => LocalAccountsRepository(ref.watch(appDatabaseProvider)),
);

/// Arşivlenenler dahil tüm hesaplar, oluşturulma sırasıyla.
final accountsProvider = FutureProvider<List<Account>>((ref) {
  ref.watch(dataGenerationProvider);
  return ref.watch(accountsRepositoryProvider).fetchAll();
});

class LocalAccountsRepository implements AccountsRepository {
  LocalAccountsRepository(this._db);

  final AppDatabase _db;

  @override
  Future<List<Account>> fetchAll() => guardData(
    () => _db
        .select('SELECT * FROM account_balances ORDER BY created_at, seq')
        .map(Account.fromJson)
        .toList(),
  );

  @override
  Future<void> create({required String name, required int openingBalance}) =>
      guardData(
        () => _db.execute(
          'INSERT INTO accounts (id, name, opening_balance) VALUES (?, ?, ?)',
          [newId(), name, openingBalance],
        ),
      );

  @override
  Future<void> update(
    String id, {
    required String name,
    required int openingBalance,
  }) => guardData(
    () => _db.execute(
      'UPDATE accounts SET name = ?, opening_balance = ? WHERE id = ?',
      [name, openingBalance, id],
    ),
  );

  @override
  Future<void> setArchived(String id, {required bool archived}) => guardData(
    () => _db.execute('UPDATE accounts SET archived_at = ? WHERE id = ?', [
      archived ? AppDatabase.now() : null,
      id,
    ]),
  );
}
