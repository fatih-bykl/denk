import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/data_generation.dart';

import '../../../core/date/dates.dart';
import '../../debts/data/debts_repository.dart';
import '../../transactions/data/transactions_repository.dart';
import '../data/schedule_repository.dart';
import '../domain/occurrence.dart';
import '../domain/payment_schedule.dart';

/// Dönemler bugünden bu kadar ay ileriye kadar oluşturulur.
const horizonMonths = 12;

/// Bir planın dönemlerini kuralına göre eşitler.
///
/// İçinde bulunulan ayın başından ufka kadar bekleyen dönemler yeniden hesaplanır;
/// geçmiş aylardaki gecikmiş dönemler ile ödenmiş/atlanmış dönemler korunur.
/// Pasif planın gelecekteki bekleyen dönemleri silinir.
///
/// Taksitli borç planında [debtTotal] verilir: taksit tutarları toplamdan
/// bölünür ve kuruş farkı son taksite eklenir.
Future<void> syncSchedule(
  ScheduleRepository repo,
  PaymentSchedule schedule,
  DateTime today, {
  int? debtTotal,
}) {
  final from = Dates.monthStart(today);
  if (!schedule.isActive) {
    return repo.syncOccurrences(schedule.id, from, const []);
  }
  final horizon = Dates.addMonths(from, horizonMonths + 1);
  final limit = schedule.occurrenceLimit;
  final split = debtTotal != null && limit != null
      ? splitInstallments(debtTotal, limit)
      : null;

  // Taksit sırası geçmiş vadeler dahil sayılır, bu yüzden indeks tüm listeden alınır.
  final all = schedule.rule.datesUntil(horizon).toList();
  final dates = <DateTime>[];
  final amounts = <int>[];
  for (var i = 0; i < all.length; i++) {
    if (all[i].isBefore(from)) continue;
    dates.add(all[i]);
    if (split != null) amounts.add(split[i]);
  }
  return repo.syncOccurrences(
    schedule.id,
    from,
    dates,
    amounts: split == null ? null : amounts,
  );
}

/// [total] kuruşu [count] taksite böler; kuruş farkı son taksite eklenir.
/// 100000 / 3 → [33333, 33333, 33334]
List<int> splitInstallments(int total, int count) {
  final base = total ~/ count;
  return [for (var i = 0; i < count - 1; i++) base, total - base * (count - 1)];
}

final schedulesProvider = FutureProvider<List<PaymentSchedule>>((ref) {
  ref.watch(dataGenerationProvider);
  return ref.watch(scheduleRepositoryProvider).fetchSchedules();
});

/// Uygulama açıldığında bir kez çalışır: aktif planların dönemlerini ufka kadar
/// uzatır (ör. süresiz kira planına yeni ayın dönemi eklenir).
final horizonSyncProvider = FutureProvider<void>((ref) async {
  final repo = ref.watch(scheduleRepositoryProvider);
  final today = ref.watch(todayProvider);
  final schedules = await ref.watch(schedulesProvider.future);
  final active = schedules.where((s) => s.isActive).toList();
  final debtTotals = active.any((s) => s.debtId != null)
      ? {
          for (final d in await ref.watch(debtsProvider.future))
            d.id: d.totalAmount,
        }
      : const <String, int>{};
  for (final s in active) {
    await syncSchedule(repo, s, today, debtTotal: debtTotals[s.debtId]);
  }
});

/// Bir ayın dönemleri. Anahtar ayın ilk günüdür.
final monthOccurrencesProvider =
    FutureProvider.family<List<Occurrence>, DateTime>((ref, month) async {
      await ref.watch(horizonSyncProvider.future);
      final start = Dates.monthStart(month);
      return ref
          .watch(scheduleRepositoryProvider)
          .fetchOccurrences(from: start, to: Dates.addMonths(start, 1));
    });

/// Vadesi geçmiş, ödenmemiş dönemler.
final overdueOccurrencesProvider = FutureProvider<List<Occurrence>>((
  ref,
) async {
  await ref.watch(horizonSyncProvider.future);
  return ref
      .watch(scheduleRepositoryProvider)
      .fetchOverdue(ref.watch(todayProvider));
});

/// Plan veya dönem değişikliğinden sonra yenilenecek veri. Taksit ödemesi
/// borcun kalanını ve ödeme geçmişini de değiştirdiği için borçlar da yenilenir.
void invalidateSchedule(WidgetRef ref) => ref
  ..invalidate(schedulesProvider)
  ..invalidate(monthOccurrencesProvider)
  ..invalidate(overdueOccurrencesProvider)
  ..invalidate(debtsProvider)
  ..invalidate(debtTransactionsProvider);
