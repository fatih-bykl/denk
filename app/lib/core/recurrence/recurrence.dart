enum Frequency {
  once('Tek seferlik', 'Tek seferlik'),
  weekly('Haftalık', 'hafta'),
  monthly('Aylık', 'ay'),
  yearly('Yıllık', 'yıl');

  const Frequency(this.label, this.unit);

  final String label;

  /// "Her 2 ay" gibi ifadelerde kullanılan birim.
  final String unit;

  static Frequency fromName(String name) =>
      values.firstWhere((f) => f.name == name);
}

/// Bir ödeme planının tekrar kuralı. Tarihler saatsizdir (yerel gece yarısı).
class RecurrenceRule {
  const RecurrenceRule({
    required this.frequency,
    required this.start,
    this.interval = 1,
    this.end,
    this.limit,
  }) : assert(interval >= 1);

  final Frequency frequency;

  /// İlk vade günü. Aylık ve yıllık tekrarda gün bu tarihten alınır.
  final DateTime start;
  final int interval;

  /// Bu tarihten sonra vade yok (dahil).
  final DateTime? end;

  /// Toplam vade sayısı (ör. 12 taksit). Başlangıçtan itibaren sayılır.
  final int? limit;

  /// [n]. vade (0 tabanlı). Aylık/yıllık tekrar her seferinde başlangıç gününe
  /// göre hesaplanır; kısa aylarda ayın son gününe düşer ve sonraki ayda
  /// asıl güne geri döner (31 Ocak → 28 Şubat → 31 Mart).
  DateTime nth(int n) => switch (frequency) {
    Frequency.once => start,
    Frequency.weekly => DateTime(
      start.year,
      start.month,
      start.day + 7 * interval * n,
    ),
    Frequency.monthly => _addMonthsClamped(start, interval * n),
    Frequency.yearly => _addMonthsClamped(start, 12 * interval * n),
  };

  /// [until] dahil olmak üzere o güne kadarki tüm vadeler, sırayla.
  Iterable<DateTime> datesUntil(DateTime until) sync* {
    final maxCount = frequency == Frequency.once ? 1 : limit;
    for (var n = 0; maxCount == null || n < maxCount; n++) {
      final date = nth(n);
      if (date.isAfter(until)) return;
      if (end != null && date.isAfter(end!)) return;
      yield date;
    }
  }

  /// [from] ile [until] arasındaki (ikisi de dahil) vadeler.
  List<DateTime> datesBetween(DateTime from, DateTime until) =>
      datesUntil(until).where((d) => !d.isBefore(from)).toList();

  static DateTime _addMonthsClamped(DateTime date, int months) {
    final firstOfTarget = DateTime(date.year, date.month + months);
    final lastDay = DateTime(
      firstOfTarget.year,
      firstOfTarget.month + 1,
      0,
    ).day;
    return DateTime(
      firstOfTarget.year,
      firstOfTarget.month,
      date.day > lastDay ? lastDay : date.day,
    );
  }
}
