import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/date/dates.dart';
import '../../categories/data/categories_repository.dart';
import '../../categories/domain/category.dart';
import '../../transactions/data/transactions_repository.dart';
import '../../transactions/domain/transaction.dart';
import 'dashboard_providers.dart';

/// Halka grafikte ayrı dilim olarak gösterilen en fazla kategori sayısı;
/// kalanlar "Diğer" diliminde toplanır (liste hepsini ayrı gösterir).
const maxChartSlices = 6;

/// Özet ekranında incelenen ay (ayın ilk günü). Varsayılan: içinde bulunulan ay.
final dashboardMonthProvider = NotifierProvider<DashboardMonth, DateTime>(
  DashboardMonth.new,
);

class DashboardMonth extends Notifier<DateTime> {
  @override
  DateTime build() => Dates.monthStart(ref.watch(todayProvider));

  DateTime get _current => Dates.monthStart(ref.read(todayProvider));

  bool get canGoNext => state.isBefore(_current);

  void previous() => state = Dates.addMonths(state, -1);

  void next() {
    if (canGoNext) state = Dates.addMonths(state, 1);
  }
}

/// Bir kategorinin ay içindeki toplamı ve tüm toplamdaki payı.
class CategoryShare {
  const CategoryShare({
    required this.categoryId,
    required this.name,
    required this.icon,
    required this.amount,
    required this.share,
  });

  /// Kategorisiz işlemler için `null`.
  final String? categoryId;
  final String name;
  final String? icon;

  /// Kuruş.
  final int amount;

  /// 0–1 arası.
  final double share;
}

class CategoryBreakdown {
  const CategoryBreakdown({required this.items, required this.total});

  /// Tutara göre büyükten küçüğe.
  final List<CategoryShare> items;

  /// Kuruş.
  final int total;

  bool get isEmpty => total == 0;
}

/// Bir ayın gelir ya da giderlerini kategorilere göre toplar.
CategoryBreakdown breakdownOf(
  Iterable<Transaction> transactions,
  EntryKind kind,
  List<Category> categories,
) {
  final byId = {for (final c in categories) c.id: c};
  final sums = <String?, int>{};
  for (final t in transactions) {
    if (t.type != kind) continue;
    // Silinmiş (bilinmeyen) kategori de kategorisiz sayılır.
    final key = byId.containsKey(t.categoryId) ? t.categoryId : null;
    sums[key] = (sums[key] ?? 0) + t.amount;
  }
  final total = sums.values.fold(0, (s, v) => s + v);
  final items =
      [
        for (final MapEntry(key: id, value: amount) in sums.entries)
          CategoryShare(
            categoryId: id,
            name: id == null ? 'Kategorisiz' : byId[id]!.name,
            icon: id == null ? null : byId[id]!.icon,
            amount: amount,
            share: total == 0 ? 0 : amount / total,
          ),
      ]..sort((a, b) {
        final byAmount = b.amount.compareTo(a.amount);
        return byAmount != 0 ? byAmount : a.name.compareTo(b.name);
      });
  return CategoryBreakdown(items: items, total: total);
}

/// İncelenen ayın kategori dağılımı. İşlemler sekmesiyle aynı önbelleği kullanır.
final categoryBreakdownProvider =
    FutureProvider.family<
      CategoryBreakdown,
      ({DateTime month, EntryKind kind})
    >((ref, key) async {
      final transactions = await ref.watch(
        monthTransactionsProvider(key.month).future,
      );
      final categories = await ref.watch(categoriesProvider.future);
      return breakdownOf(transactions, key.kind, categories);
    });

/// Özet ekranında halka grafiğin gösterdiği tür (gider ya da gelir).
final dashboardKindProvider = NotifierProvider<DashboardKind, EntryKind>(
  DashboardKind.new,
);

class DashboardKind extends Notifier<EntryKind> {
  @override
  EntryKind build() => EntryKind.expense;

  void set(EntryKind kind) => state = kind;
}

/// İncelenen ay ve bir önceki ayın gelir/gider toplamları.
final monthComparisonProvider =
    FutureProvider.family<({MonthFlow current, MonthFlow previous}), DateTime>((
      ref,
      month,
    ) async {
      final prevMonth = Dates.addMonths(month, -1);
      final lists = await Future.wait([
        ref.watch(monthTransactionsProvider(month).future),
        ref.watch(monthTransactionsProvider(prevMonth).future),
      ]);
      return (
        current: MonthFlow.of(month, lists[0]),
        previous: MonthFlow.of(prevMonth, lists[1]),
      );
    });
