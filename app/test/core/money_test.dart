import 'package:denk/core/money/money.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Money.format', () {
    test('binlik ayraç ve kuruş', () {
      expect(Money.format(125050), '1.250,50 ₺');
      expect(Money.format(0), '0,00 ₺');
      expect(Money.format(5), '0,05 ₺');
      expect(Money.format(100000000), '1.000.000,00 ₺');
      expect(Money.format(99999), '999,99 ₺');
    });

    test('eksi tutar ve sembolsüz', () {
      expect(Money.format(-125050), '-1.250,50 ₺');
      expect(Money.format(-5), '-0,05 ₺');
      expect(Money.format(125050, symbol: false), '1.250,50');
    });
  });

  group('Money.parse', () {
    test('geçerli biçimler', () {
      expect(Money.parse('1250'), 125000);
      expect(Money.parse('1250,5'), 125050);
      expect(Money.parse('1.250,50'), 125050);
      expect(Money.parse('1250.50'), 125050);
      expect(Money.parse(' 1.250,50 ₺ '), 125050);
      expect(Money.parse('0,05'), 5);
      expect(Money.parse('1.000.000'), 100000000);
    });

    test('biçimlendirilmiş değer geri okunur', () {
      for (final v in [0, 5, 99, 125050, 100000000, 123456789]) {
        expect(Money.parse(Money.format(v, symbol: false)), v);
      }
    });

    test('eksi tutar yalnızca izin verilirse', () {
      expect(Money.parse('-300'), isNull);
      expect(Money.parse('-300', allowNegative: true), -30000);
      expect(Money.parse('-1.250,50', allowNegative: true), -125050);
    });

    test('geçersiz girdiler', () {
      for (final s in [
        '',
        ' ',
        'abc',
        '1,234',
        '12,3,4',
        '1.25.0',
        '1.2345',
        ',5',
        '--3',
        '1e5',
      ]) {
        expect(Money.parse(s), isNull, reason: s);
      }
    });

    test('üst sınır', () {
      expect(Money.parse('1.000.000.000.000'), Money.maxKurus);
      expect(Money.parse('1.000.000.000.000,01'), isNull);
      expect(Money.parse('99999999999999999999'), isNull);
    });
  });
}
