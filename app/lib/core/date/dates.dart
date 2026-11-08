import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

/// Bugünün tarihi (saatsiz). Testlerde sabit bir günle override edilir.
final todayProvider = Provider<DateTime>((ref) {
  final now = DateTime.now();
  return DateTime(now.year, now.month, now.day);
});

abstract final class Dates {
  static const _locale = 'tr_TR';

  static DateTime dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);
  static DateTime monthStart(DateTime d) => DateTime(d.year, d.month);

  /// Ay ekler ve günü 1'e çeker (ay gezintisi için). Gün korunacaksa [addMonthsKeepDay].
  static DateTime addMonths(DateTime month, int count) =>
      DateTime(month.year, month.month + count);

  /// Ay ekler, günü korur; hedef ayda o gün yoksa ayın son günü (31 Oca + 1 → 28 Şub).
  static DateTime addMonthsKeepDay(DateTime d, int count) {
    final target = DateTime(d.year, d.month + count);
    final lastDay = DateTime(target.year, target.month + 1, 0).day;
    return DateTime(
      target.year,
      target.month,
      d.day > lastDay ? lastDay : d.day,
    );
  }

  /// Veritabanındaki `date` sütunu biçimi: 2026-11-05.
  static String toDb(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';

  /// "2026-11-05" → yerel gece yarısı.
  static DateTime fromDb(String s) {
    final p = s.split('-').map(int.parse).toList();
    return DateTime(p[0], p[1], p[2]);
  }

  /// "Kasım 2026"
  static String month(DateTime m) => DateFormat('MMMM y', _locale).format(m);

  /// "5 Kasım 2026"
  static String long(DateTime d) => DateFormat('d MMMM y', _locale).format(d);

  /// "5 Kasım 2026 14:32"
  static String dateTime(DateTime d) =>
      DateFormat('d MMMM y HH:mm', _locale).format(d);

  /// "Bugün", "Dün" veya "5 Kasım Çarşamba"
  static String day(DateTime d, DateTime today) {
    final diff = dateOnly(today).difference(dateOnly(d)).inDays;
    if (diff == 0) return 'Bugün';
    if (diff == 1) return 'Dün';
    return DateFormat('d MMMM EEEE', _locale).format(d);
  }
}
