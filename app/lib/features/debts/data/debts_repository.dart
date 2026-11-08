import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/data_generation.dart';

import '../../../core/errors/data_failure.dart';
import '../../../core/database/app_database.dart';
import '../../../core/database/sql.dart';
import '../domain/debt.dart';

/// Tüm metotlar hata durumunda [DataFailure] fırlatır.
abstract interface class DebtsRepository {
  Future<List<Debt>> fetchAll();

  /// Yeni borcun kimliğini döndürür.
  Future<String> create(DebtDraft draft);
  Future<void> update(String id, DebtDraft draft);

  /// Taksit planı ve bekleyen taksitler de silinir; yapılmış ödemelerin
  /// işlem kayıtları kalır (borç bağları kopar).
  Future<void> delete(String id);
  Future<void> setClosed(String id, {required bool closed});
}

final debtsRepositoryProvider = Provider<DebtsRepository>(
  (ref) => LocalDebtsRepository(ref.watch(appDatabaseProvider)),
);

/// Kapalılar dahil tüm borç ve alacaklar, oluşturulma sırasıyla.
final debtsProvider = FutureProvider<List<Debt>>((ref) {
  ref.watch(dataGenerationProvider);
  return ref.watch(debtsRepositoryProvider).fetchAll();
});

class LocalDebtsRepository implements DebtsRepository {
  LocalDebtsRepository(this._db);

  final AppDatabase _db;

  @override
  Future<List<Debt>> fetchAll() => guardData(
    () => _db
        .select('SELECT * FROM debt_balances ORDER BY created_at, seq')
        .map(Debt.fromJson)
        .toList(),
  );

  @override
  Future<String> create(DebtDraft draft) => guardData(() {
    final id = newId();
    _db.insert('debts', {'id': id, ...draft.toJson()});
    return id;
  });

  @override
  Future<void> update(String id, DebtDraft draft) =>
      guardData(() => _db.updateById('debts', id, draft.toJson()));

  @override
  Future<void> delete(String id) =>
      guardData(() => _db.execute('DELETE FROM debts WHERE id = ?', [id]));

  @override
  Future<void> setClosed(String id, {required bool closed}) => guardData(
    () => _db.execute('UPDATE debts SET closed_at = ? WHERE id = ?', [
      closed ? AppDatabase.now() : null,
      id,
    ]),
  );
}
