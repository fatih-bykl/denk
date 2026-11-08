import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/date/dates.dart';
import '../../../core/errors/data_failure.dart';
import '../../../core/database/app_database.dart';
import '../../../core/database/sql.dart';
import '../domain/occurrence.dart';
import '../domain/payment_schedule.dart';

/// Tüm metotlar hata durumunda [DataFailure] fırlatır.
abstract interface class ScheduleRepository {
  Future<List<PaymentSchedule>> fetchSchedules();

  /// Yeni planın kimliğini döndürür.
  Future<String> createSchedule(ScheduleDraft draft);
  Future<void> updateSchedule(String id, ScheduleDraft draft);

  /// Plan ve bekleyen/atlanan dönemleri silinir; ödemelerden oluşan işlemler kalır.
  Future<void> deleteSchedule(String id);

  /// [from] (dahil) ile [to] (hariç) arasındaki dönemler, vadeye göre sıralı.
  Future<List<Occurrence>> fetchOccurrences({DateTime? from, DateTime? to});

  /// Vadesi [before] tarihinden önce olan ve ödenmemiş dönemler.
  Future<List<Occurrence>> fetchOverdue(DateTime before);

  /// Planın [from] sonrasındaki bekleyen dönemlerini [dates] ile eşitler.
  /// [amounts] verilirse her tarihin tutarı odur; yoksa plan tutarı kullanılır.
  Future<void> syncOccurrences(
    String scheduleId,
    DateTime from,
    List<DateTime> dates, {
    List<int>? amounts,
  });

  /// Dönemi öder; oluşan işlemin kimliğini döndürür.
  Future<String> pay(
    String occurrenceId, {
    required String accountId,
    required int amount,
    required DateTime paidOn,
  });

  /// Dönemi atlar ya da atlamayı geri alır.
  Future<void> setSkipped(String occurrenceId, {required bool skipped});
}

final scheduleRepositoryProvider = Provider<ScheduleRepository>(
  (ref) => LocalScheduleRepository(ref.watch(appDatabaseProvider)),
);

class LocalScheduleRepository implements ScheduleRepository {
  LocalScheduleRepository(this._db);

  final AppDatabase _db;

  /// Dönem satırı + planın adı ve yönü (ekranlar dönemi planla birlikte gösterir).
  static const _occurrenceSelect = """
SELECT o.*, s.title AS schedule_title, s.flow AS schedule_flow
FROM payment_occurrences o
JOIN payment_schedules s ON s.id = o.schedule_id""";

  static Occurrence _occurrence(Map<String, Object?> row) =>
      Occurrence.fromJson({
        ...row,
        'payment_schedules': {
          'title': row['schedule_title'],
          'flow': row['schedule_flow'],
        },
      });

  @override
  Future<List<PaymentSchedule>> fetchSchedules() => guardData(
    () => _db
        .select('SELECT * FROM payment_schedules ORDER BY title, rowid')
        .map(
          (r) => PaymentSchedule.fromJson({
            ...r,
            'is_active': r['is_active'] == 1,
          }),
        )
        .toList(),
  );

  @override
  Future<String> createSchedule(ScheduleDraft draft) => guardData(() {
    final id = newId();
    _db.insert('payment_schedules', {'id': id, ...draft.toJson()});
    return id;
  });

  @override
  Future<void> updateSchedule(String id, ScheduleDraft draft) =>
      guardData(() => _db.updateById('payment_schedules', id, draft.toJson()));

  @override
  Future<void> deleteSchedule(String id) => guardData(
    () => _db.execute('DELETE FROM payment_schedules WHERE id = ?', [id]),
  );

  @override
  Future<List<Occurrence>> fetchOccurrences({DateTime? from, DateTime? to}) =>
      guardData(() {
        final where = <String>[];
        final params = <Object?>[];
        if (from != null) {
          where.add('o.due_date >= ?');
          params.add(Dates.toDb(from));
        }
        if (to != null) {
          where.add('o.due_date < ?');
          params.add(Dates.toDb(to));
        }
        final filter = where.isEmpty ? '' : ' WHERE ${where.join(' AND ')}';
        return _db
            .select(
              '$_occurrenceSelect$filter ORDER BY o.due_date, o.rowid',
              params,
            )
            .map(_occurrence)
            .toList();
      });

  @override
  Future<List<Occurrence>> fetchOverdue(DateTime before) => guardData(
    () => _db
        .select(
          "$_occurrenceSelect WHERE o.status = 'pending' AND o.due_date < ? "
          'ORDER BY o.due_date, o.rowid',
          [Dates.toDb(before)],
        )
        .map(_occurrence)
        .toList(),
  );

  /// Planın [from] sonrasındaki bekleyen dönemlerini [dates] ile eşitler:
  /// listede olmayan bekleyenler silinir, eksikler eklenir, tutarlar güncellenir.
  /// Ödenmiş ve atlanmış dönemlere dokunulmaz.
  @override
  Future<void> syncOccurrences(
    String scheduleId,
    DateTime from,
    List<DateTime> dates, {
    List<int>? amounts,
  }) => guardData(() {
    _db.transaction(() {
      final schedule = _db.selectOne(
        'SELECT amount FROM payment_schedules WHERE id = ?',
        [scheduleId],
      );
      if (schedule == null) throw DataFailure.notFound;
      final planAmount = schedule['amount']! as int;
      final fromDb = Dates.toDb(from);

      // İstenen dönemler: tarih → tutar. Tutar listesi kısaysa eksikler plan tutarını alır.
      final wanted = <String, int>{
        for (var i = 0; i < dates.length; i++)
          Dates.toDb(dates[i]): (amounts != null && i < amounts.length)
              ? amounts[i]
              : planAmount,
      }..removeWhere((date, _) => date.compareTo(fromDb) < 0);

      final pending = _db.select(
        "SELECT id, due_date, amount FROM payment_occurrences "
        "WHERE schedule_id = ? AND status = 'pending' AND due_date >= ?",
        [scheduleId, fromDb],
      );
      for (final row in pending) {
        final due = row['due_date']! as String;
        final amount = wanted[due];
        if (amount == null) {
          _db.execute('DELETE FROM payment_occurrences WHERE id = ?', [
            row['id'],
          ]);
        } else if (amount != row['amount']) {
          _db.execute(
            'UPDATE payment_occurrences SET amount = ? WHERE id = ?',
            [amount, row['id']],
          );
        }
      }

      // Var olan (ödenmiş/atlanmış dahil) dönemlere dokunulmaz.
      for (final MapEntry(key: due, value: amount) in wanted.entries) {
        _db.execute(
          'INSERT OR IGNORE INTO payment_occurrences (id, schedule_id, due_date, amount) '
          'VALUES (?, ?, ?, ?)',
          [newId(), scheduleId, due, amount],
        );
      }
    });
  });

  /// Dönemi öder: işlemi oluşturur ve dönemi kapatır. İkisi birlikte olur ya da hiçbiri.
  @override
  Future<String> pay(
    String occurrenceId, {
    required String accountId,
    required int amount,
    required DateTime paidOn,
  }) => guardData(
    () => _db.transaction(() {
      final r = _db.selectOne(
        'SELECT o.status, s.flow, s.category_id, s.debt_id, s.title '
        'FROM payment_occurrences o '
        'JOIN payment_schedules s ON s.id = o.schedule_id '
        'WHERE o.id = ?',
        [occurrenceId],
      );
      if (r == null) throw DataFailure.notFound;
      if (r['status'] != OccurrenceStatus.pending.name) {
        throw DataFailure.alreadyClosed;
      }

      final transactionId = newId();
      _db.insert('transactions', {
        'id': transactionId,
        'account_id': accountId,
        'category_id': r['category_id'],
        'type': CashFlow.fromName(r['flow']! as String).entryKind.name,
        'amount': amount,
        'occurred_on': Dates.toDb(paidOn),
        'note': r['title'],
        'debt_id': r['debt_id'],
      });
      _db.execute(
        "UPDATE payment_occurrences SET status = 'paid', transaction_id = ?, amount = ? "
        'WHERE id = ?',
        [transactionId, amount, occurrenceId],
      );
      return transactionId;
    }),
  );

  @override
  Future<void> setSkipped(String occurrenceId, {required bool skipped}) =>
      guardData(
        () => _db.execute(
          'UPDATE payment_occurrences SET status = ? WHERE id = ?',
          [
            skipped
                ? OccurrenceStatus.skipped.name
                : OccurrenceStatus.pending.name,
            occurrenceId,
          ],
        ),
      );
}
