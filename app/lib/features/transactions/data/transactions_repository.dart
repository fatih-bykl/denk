import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/data_generation.dart';

import '../../../core/date/dates.dart';
import '../../../core/errors/data_failure.dart';
import '../../../core/database/app_database.dart';
import '../../../core/database/sql.dart';
import '../domain/transaction.dart';

/// Tüm metotlar hata durumunda [DataFailure] fırlatır.
abstract interface class TransactionsRepository {
  /// [month] ayındaki işlemler, en yeniden eskiye.
  Future<List<Transaction>> fetchMonth(DateTime month);

  /// Bir borca bağlı işlemler (ödemeler/tahsilatlar), en yeniden eskiye.
  Future<List<Transaction>> fetchByDebt(String debtId);
  Future<void> create(TransactionDraft draft);
  Future<void> update(String id, TransactionDraft draft);
  Future<void> delete(String id);
}

final transactionsRepositoryProvider = Provider<TransactionsRepository>(
  (ref) => LocalTransactionsRepository(ref.watch(appDatabaseProvider)),
);

/// Bir ayın işlemleri. Anahtar ayın ilk günüdür.
final monthTransactionsProvider =
    FutureProvider.family<List<Transaction>, DateTime>((ref, month) {
      ref.watch(dataGenerationProvider);
      return ref.watch(transactionsRepositoryProvider).fetchMonth(month);
    });

/// Bir borcun ödeme geçmişi.
final debtTransactionsProvider =
    FutureProvider.family<List<Transaction>, String>((ref, debtId) {
      ref.watch(dataGenerationProvider);
      return ref.watch(transactionsRepositoryProvider).fetchByDebt(debtId);
    });

class LocalTransactionsRepository implements TransactionsRepository {
  LocalTransactionsRepository(this._db);

  final AppDatabase _db;

  @override
  Future<List<Transaction>> fetchMonth(DateTime month) => guardData(() {
    final start = Dates.monthStart(month);
    return _db
        .select(
          'SELECT * FROM transactions WHERE occurred_on >= ? AND occurred_on < ? '
          'ORDER BY occurred_on DESC, created_at DESC, rowid DESC',
          [Dates.toDb(start), Dates.toDb(Dates.addMonths(start, 1))],
        )
        .map(Transaction.fromJson)
        .toList();
  });

  @override
  Future<List<Transaction>> fetchByDebt(String debtId) => guardData(
    () => _db
        .select(
          'SELECT * FROM transactions WHERE debt_id = ? '
          'ORDER BY occurred_on DESC, created_at DESC, rowid DESC',
          [debtId],
        )
        .map(Transaction.fromJson)
        .toList(),
  );

  @override
  Future<void> create(TransactionDraft draft) => guardData(
    () => _db.insert('transactions', {'id': newId(), ...draft.toJson()}),
  );

  @override
  Future<void> update(String id, TransactionDraft draft) =>
      guardData(() => _db.updateById('transactions', id, draft.toJson()));

  @override
  Future<void> delete(String id) => guardData(
    () => _db.execute('DELETE FROM transactions WHERE id = ?', [id]),
  );
}
