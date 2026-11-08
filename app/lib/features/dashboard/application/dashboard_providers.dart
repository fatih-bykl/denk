import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/date/dates.dart';
import '../../categories/domain/category.dart';
import '../../schedule/application/schedule_providers.dart';
import '../../schedule/data/schedule_repository.dart';
import '../../schedule/domain/occurrence.dart';
import '../../schedule/domain/payment_schedule.dart';
import '../../transactions/data/transactions_repository.dart';
import '../../transactions/domain/transaction.dart';

/// Nakit akışı grafiğinde gösterilen ay sayısı (içinde bulunulan ay dahil).
const cashFlowMonths = 6;

class MonthFlow {
  const MonthFlow({
    required this.month,
    required this.income,
    required this.expense,
  });

  /// Bir ayın işlemlerinden gelir ve gider toplamı (kuruş).
  factory MonthFlow.of(DateTime month, Iterable<Transaction> transactions) {
    var income = 0;
    var expense = 0;
    for (final t in transactions) {
      if (t.type == EntryKind.income) {
        income += t.amount;
      } else {
        expense += t.amount;
      }
    }
    return MonthFlow(month: month, income: income, expense: expense);
  }

  final DateTime month;
  final int income;
  final int expense;

  int get net => income - expense;
}

/// Son [cashFlowMonths] ayın gelir/gider toplamları, eskiden yeniye.
/// Aylık işlem sağlayıcısını kullanır; İşlemler sekmesiyle aynı önbelleği paylaşır.
final cashFlowProvider = FutureProvider<List<MonthFlow>>((ref) async {
  final current = Dates.monthStart(ref.watch(todayProvider));
  final months = [
    for (var i = cashFlowMonths - 1; i >= 0; i--) Dates.addMonths(current, -i),
  ];
  final lists = await Future.wait([
    for (final m in months) ref.watch(monthTransactionsProvider(m).future),
  ]);
  return [
    for (var i = 0; i < months.length; i++) MonthFlow.of(months[i], lists[i]),
  ];
});

/// Bugünden itibaren ödenmemiş ilk 3 dönem.
final upcomingOccurrencesProvider = FutureProvider<List<Occurrence>>((
  ref,
) async {
  await ref.watch(horizonSyncProvider.future);
  final today = ref.watch(todayProvider);
  final items = await ref
      .watch(scheduleRepositoryProvider)
      .fetchOccurrences(from: today);
  return items.where((o) => o.isPending).take(3).toList();
});

class DuePayments {
  const DuePayments({
    required this.thisMonth,
    required this.overdue,
    required this.overdueCount,
  });

  /// Bu ay vadesi gelen ve henüz ödenmemiş ödemeler (tahsilatlar hariç).
  final int thisMonth;

  /// Önceki aylardan kalan, ödenmemiş ödemeler.
  final int overdue;
  final int overdueCount;
}

/// "Bu ay ödenecek": bu ayın bekleyen ödemeleri. Vadesi bu ay içinde geçmiş
/// olanlar da buraya dahildir; önceki aylardan kalanlar ayrıca gösterilir.
final duePaymentsProvider = FutureProvider<DuePayments>((ref) async {
  final today = ref.watch(todayProvider);
  final month = await ref.watch(
    monthOccurrencesProvider(Dates.monthStart(today)).future,
  );
  final overdue = await ref.watch(overdueOccurrencesProvider.future);
  bool isPayment(Occurrence o) => o.isPending && o.flow == CashFlow.outflow;
  final earlier = overdue
      .where((o) => isPayment(o) && o.dueDate.isBefore(Dates.monthStart(today)))
      .toList();
  return DuePayments(
    thisMonth: month.where(isPayment).fold(0, (s, o) => s + o.amount),
    overdue: earlier.fold(0, (s, o) => s + o.amount),
    overdueCount: earlier.length,
  );
});
