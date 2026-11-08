import 'package:denk/core/recurrence/recurrence.dart';
import 'package:flutter_test/flutter_test.dart';

DateTime d(int y, int m, int day) => DateTime(y, m, day);

List<DateTime> first(RecurrenceRule rule, int count) =>
    rule.datesUntil(d(2100, 1, 1)).take(count).toList();

void main() {
  group('aylık', () {
    test('ayın 31\'i kısa aylarda son güne düşer, sonra 31\'e döner', () {
      final rule = RecurrenceRule(
        frequency: Frequency.monthly,
        start: d(2026, 1, 31),
      );
      expect(first(rule, 6), [
        d(2026, 1, 31),
        d(2026, 2, 28),
        d(2026, 3, 31),
        d(2026, 4, 30),
        d(2026, 5, 31),
        d(2026, 6, 30),
      ]);
    });

    test('artık yılda 29 Şubat', () {
      final rule = RecurrenceRule(
        frequency: Frequency.monthly,
        start: d(2027, 12, 30),
      );
      expect(first(rule, 3), [d(2027, 12, 30), d(2028, 1, 30), d(2028, 2, 29)]);
    });

    test('ayın 29\'u artık olmayan yılda 28 Şubat', () {
      final rule = RecurrenceRule(
        frequency: Frequency.monthly,
        start: d(2026, 1, 29),
      );
      expect(first(rule, 3), [d(2026, 1, 29), d(2026, 2, 28), d(2026, 3, 29)]);
    });

    test('her 3 ayda bir ve yıl geçişi', () {
      final rule = RecurrenceRule(
        frequency: Frequency.monthly,
        start: d(2026, 11, 15),
        interval: 3,
      );
      expect(first(rule, 3), [d(2026, 11, 15), d(2027, 2, 15), d(2027, 5, 15)]);
    });

    test('12 taksit sınırı', () {
      final rule = RecurrenceRule(
        frequency: Frequency.monthly,
        start: d(2026, 11, 5),
        limit: 12,
      );
      final dates = rule.datesUntil(d(2030, 1, 1)).toList();
      expect(dates.length, 12);
      expect(dates.last, d(2027, 10, 5));
    });

    test('bitiş tarihi dahil', () {
      final rule = RecurrenceRule(
        frequency: Frequency.monthly,
        start: d(2026, 1, 10),
        end: d(2026, 4, 10),
      );
      expect(rule.datesUntil(d(2030, 1, 1)).toList(), [
        d(2026, 1, 10),
        d(2026, 2, 10),
        d(2026, 3, 10),
        d(2026, 4, 10),
      ]);
    });
  });

  group('yıllık', () {
    test('29 Şubat artık olmayan yıllarda 28 Şubat', () {
      final rule = RecurrenceRule(
        frequency: Frequency.yearly,
        start: d(2028, 2, 29),
      );
      expect(first(rule, 5), [
        d(2028, 2, 29),
        d(2029, 2, 28),
        d(2030, 2, 28),
        d(2031, 2, 28),
        d(2032, 2, 29),
      ]);
    });

    test('her 2 yılda bir', () {
      final rule = RecurrenceRule(
        frequency: Frequency.yearly,
        start: d(2026, 6, 1),
        interval: 2,
      );
      expect(first(rule, 3), [d(2026, 6, 1), d(2028, 6, 1), d(2030, 6, 1)]);
    });
  });

  group('haftalık', () {
    test('ay ve yıl geçişi', () {
      final rule = RecurrenceRule(
        frequency: Frequency.weekly,
        start: d(2026, 12, 24),
      );
      expect(first(rule, 3), [d(2026, 12, 24), d(2026, 12, 31), d(2027, 1, 7)]);
    });

    test('yaz saati geçişinde gün kaymaz', () {
      // Avrupa'da saat 29 Mart 2026'da ileri alınır; tarihler yine pazartesi gece yarısı.
      final rule = RecurrenceRule(
        frequency: Frequency.weekly,
        start: d(2026, 3, 23),
      );
      for (final date in first(rule, 4)) {
        expect(date.hour, 0);
        expect(date.weekday, DateTime.monday);
      }
    });

    test('her 2 haftada bir', () {
      final rule = RecurrenceRule(
        frequency: Frequency.weekly,
        start: d(2026, 11, 2),
        interval: 2,
      );
      expect(first(rule, 3), [
        d(2026, 11, 2),
        d(2026, 11, 16),
        d(2026, 11, 30),
      ]);
    });
  });

  test('tek seferlik yalnızca bir vade üretir', () {
    final rule = RecurrenceRule(
      frequency: Frequency.once,
      start: d(2026, 11, 20),
      limit: 5,
    );
    expect(rule.datesUntil(d(2030, 1, 1)).toList(), [d(2026, 11, 20)]);
    expect(rule.datesUntil(d(2026, 11, 19)).toList(), isEmpty);
  });

  test('datesBetween: geçmiş vadeler atlanır ama taksit sayısına dahildir', () {
    // 6 taksit Eylül'de başladı; Kasım'dan itibaren 4 taksit kaldı.
    final rule = RecurrenceRule(
      frequency: Frequency.monthly,
      start: d(2026, 9, 15),
      limit: 6,
    );
    expect(rule.datesBetween(d(2026, 11, 1), d(2027, 11, 1)), [
      d(2026, 11, 15),
      d(2026, 12, 15),
      d(2027, 1, 15),
      d(2027, 2, 15),
    ]);
  });
}
