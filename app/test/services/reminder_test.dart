import 'package:denk/features/schedule/domain/occurrence.dart';
import 'package:denk/features/schedule/domain/payment_schedule.dart';
import 'package:denk/services/notifications/reminder.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/test_app.dart';

RemindableOccurrence _occ(
  String id,
  DateTime due, {
  int remind = 3,
  OccurrenceStatus status = OccurrenceStatus.pending,
  CashFlow flow = CashFlow.outflow,
  int amount = 1500000,
}) => RemindableOccurrence(
  Occurrence(
    id: id,
    scheduleId: 's',
    dueDate: due,
    amount: amount,
    status: status,
    title: 'Kira',
    flow: flow,
  ),
  remind,
);

void main() {
  setUpAll(initTestLocale);

  // Şu an: 5 Kasım 2026, 14:00.
  final now = DateTime(2026, 11, 5, 14);

  test('vadeden 3 gün önce saat 09:00', () {
    final r = planReminders([_occ('a', DateTime(2026, 11, 20))], now).single;
    expect(r.at, DateTime(2026, 11, 17, 9));
    expect(r.title, 'Ödeme: Kira');
    expect(r.body, '15.000,00 ₺ · 20 Kasım 2026 (3 gün sonra)');
  });

  test('hatırlatma günü geçtiyse vade günü 09:00', () {
    final r = planReminders([_occ('a', DateTime(2026, 11, 7))], now).single;
    expect(r.at, DateTime(2026, 11, 7, 9));
    expect(r.body, endsWith('(bugün)'));
  });

  test('vade günü de geçtiyse bildirim yok', () {
    // Bugün vadeli ama saat 09:00 geçti; dün vadeli de gecikmiş.
    expect(
      planReminders([
        _occ('a', DateTime(2026, 11, 5)),
        _occ('b', DateTime(2026, 11, 4)),
      ], now),
      isEmpty,
    );
  });

  test('vade günü hatırlatması (0 gün) ve yarın ifadesi', () {
    final same = planReminders([
      _occ('a', DateTime(2026, 11, 9), remind: 0),
    ], now).single;
    expect(same.at, DateTime(2026, 11, 9, 9));
    final tomorrow = planReminders([
      _occ('b', DateTime(2026, 11, 10), remind: 1),
    ], now).single;
    expect(tomorrow.at, DateTime(2026, 11, 9, 9));
    expect(tomorrow.body, endsWith('(yarın)'));
  });

  test('ödenen ve atlanan dönemler hatırlatılmaz; tahsilat başlığı', () {
    final rs = planReminders([
      _occ('a', DateTime(2026, 11, 20), status: OccurrenceStatus.paid),
      _occ('b', DateTime(2026, 11, 20), status: OccurrenceStatus.skipped),
      _occ('c', DateTime(2026, 11, 20), flow: CashFlow.inflow),
    ], now);
    expect(rs.single.title, 'Tahsilat: Kira');
  });

  test('zamana göre sıralı ve en fazla 50', () {
    final items = [
      for (var i = 59; i >= 0; i--) _occ('o$i', DateTime(2026, 11, 10 + i)),
    ];
    final rs = planReminders(items, now);
    expect(rs.length, maxReminders);
    expect(rs.first.at, DateTime(2026, 11, 7, 9));
    for (var i = 1; i < rs.length; i++) {
      expect(rs[i].at.isBefore(rs[i - 1].at), isFalse);
    }
  });

  test('bildirim kimliği kararlı, pozitif ve farklı dönemlerde farklı', () {
    expect(reminderId('abc'), reminderId('abc'));
    final ids = {
      for (var i = 0; i < 2000; i++)
        reminderId('6f1c2a90-0000-4000-8000-${i.toString().padLeft(12, '0')}'),
    };
    expect(ids.length, 2000);
    expect(ids.every((id) => id >= 0 && id <= 0x7fffffff), isTrue);
  });

  test('uygulama içi uyarı: hatırlatma zamanı gelmiş, vadesi geçmemiş', () {
    final today = DateTime(2026, 11, 5);
    final items = [
      _occ('in-window', DateTime(2026, 11, 7)), // 4 Kasım'dan beri
      _occ('due-today', DateTime(2026, 11, 5)),
      _occ('later', DateTime(2026, 11, 20)), // 17 Kasım'da başlar
      _occ('overdue', DateTime(2026, 11, 4)), // gecikmiş listesinde
      _occ('paid', DateTime(2026, 11, 6), status: OccurrenceStatus.paid),
    ];
    expect(dueSoon(items, today).map((i) => i.occurrence.id), [
      'in-window',
      'due-today',
    ]);
    expect(testToday, today);
  });
}
