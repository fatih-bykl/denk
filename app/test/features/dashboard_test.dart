import 'package:denk/core/recurrence/recurrence.dart';
import 'package:denk/features/categories/domain/category.dart';
import 'package:denk/features/dashboard/application/dashboard_providers.dart';
import 'package:denk/features/dashboard/presentation/cash_flow_chart.dart';
import 'package:denk/features/schedule/application/schedule_providers.dart';
import 'package:denk/features/schedule/domain/occurrence.dart';
import 'package:denk/features/schedule/domain/payment_schedule.dart';
import 'package:denk/features/transactions/domain/transaction.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/fake_data_repositories.dart';
import '../helpers/test_app.dart';

/// Elle hesaplanan beklenen değerler (bugün: 5 Kasım 2026).
///
/// Hesaplar: Nakit açılış 100.000, Banka açılış 25.000, arşivli "Eski" 999 (sayılmaz).
/// İşlemler:
///   20 May  Banka  +99.999      (grafik dışında, bakiyede var)
///   15 Haz  Nakit  −1.000
///   10 Eki  Banka  −8.000
///   20 Eki  Nakit  +2.000
///    1 Kas  Banka  +40.000
///    3 Kas  Nakit  −12.500,50
/// Nakit = 100.000 − 1.000 + 2.000 − 12.500,50 = 88.499,50
/// Banka = 25.000 + 99.999 − 8.000 + 40.000   = 156.999,00
/// Toplam bakiye                               = 245.498,50
///
/// Ödemeler:
///   Kira (aylık, 10 Kas'tan 3 taksit) 15.000 → 10 Kas, 10 Ara, 10 Oca
///   Elektrik (tek, 2 Kas) 750               → bu ay, vadesi geçmiş
///   Kira geliri (tahsilat, 20 Kas) 5.000    → ödenecek değil
///   Su 300, 15 Eki, ödenmemiş               → önceki aydan gecikmiş
/// Bu ay ödenecek = 15.000 + 750 = 15.750,00 ; gecikmiş = 300,00 (1)
/// Yaklaşan 3: 10 Kas Kira, 20 Kas Kira geliri, 10 Ara Kira
late FakeAccountsRepository accounts;
late FakeTransactionsRepository transactions;
late FakeScheduleRepository schedule;

TransactionDraft _tx(String acc, EntryKind type, int kurus, DateTime day) =>
    TransactionDraft(
      accountId: acc,
      type: type,
      amount: kurus,
      occurredOn: day,
    );

Future<PaymentSchedule> _plan(
  String title,
  int kurus,
  DateTime start, {
  Frequency frequency = Frequency.once,
  int? limit,
  CashFlow flow = CashFlow.outflow,
}) async {
  final id = await schedule.createSchedule(
    ScheduleDraft(
      title: title,
      flow: flow,
      amount: kurus,
      frequency: frequency,
      startDate: start,
      occurrenceLimit: limit,
    ),
  );
  final plan = schedule.schedules.firstWhere((s) => s.id == id);
  await syncSchedule(schedule, plan, testToday);
  return plan;
}

String _text(WidgetTester tester, String key) =>
    tester.widget<Text>(find.byKey(Key(key))).data!;

void main() {
  setUpAll(initTestLocale);

  setUp(() async {
    accounts = FakeAccountsRepository();
    final cash = accounts.add('Nakit', opening: 10000000);
    final bank = accounts.add('Banka', opening: 2500000);
    accounts.add('Eski', opening: 99900, archived: true);
    transactions = FakeTransactionsRepository(accounts)
      ..add(_tx(bank, EntryKind.income, 9999900, DateTime(2026, 5, 20)))
      ..add(_tx(cash, EntryKind.expense, 100000, DateTime(2026, 6, 15)))
      ..add(_tx(bank, EntryKind.expense, 800000, DateTime(2026, 10, 10)))
      ..add(_tx(cash, EntryKind.income, 200000, DateTime(2026, 10, 20)))
      ..add(_tx(bank, EntryKind.income, 4000000, DateTime(2026, 11, 1)))
      ..add(_tx(cash, EntryKind.expense, 1250050, DateTime(2026, 11, 3)));
    schedule = FakeScheduleRepository(transactions);
    await _plan(
      'Kira',
      1500000,
      DateTime(2026, 11, 10),
      frequency: Frequency.monthly,
      limit: 3,
    );
    final electric = await _plan('Elektrik', 75000, DateTime(2026, 11, 2));
    await _plan(
      'Kira geliri',
      500000,
      DateTime(2026, 11, 20),
      flow: CashFlow.inflow,
    );
    schedule.occurrences.add(
      Occurrence(
        id: 'su',
        scheduleId: electric.id,
        dueDate: DateTime(2026, 10, 15),
        amount: 30000,
        status: OccurrenceStatus.pending,
        title: 'Su',
        flow: CashFlow.outflow,
      ),
    );
  });

  Future<void> open(WidgetTester tester) => pumpTestApp(
    tester,
    accounts: accounts,
    transactions: transactions,
    schedule: schedule,
    size: const Size(420, 2000),
  );

  testWidgets('özet rakamları elle hesaplananla aynı (bitti kriteri)', (
    tester,
  ) async {
    await open(tester);

    expect(_text(tester, 'dash-balance'), '245.498,50 ₺');
    expect(find.text('2 hesap'), findsOneWidget);
    expect(_text(tester, 'dash-due'), '15.750,00 ₺');
    expect(_text(tester, 'dash-overdue'), '300,00 ₺');
    expect(find.text('Gecikmiş (1)'), findsOneWidget);
  });

  testWidgets('yaklaşan ilk 3 ödeme sırayla', (tester) async {
    await open(tester);

    final titles = tester
        .widgetList<ListTile>(find.byType(ListTile))
        .map((t) => (t.title as Text).data)
        .toList();
    expect(titles, ['Kira', 'Kira geliri', 'Kira']);
    expect(find.text('10 Kasım 2026 · 5 gün sonra'), findsOneWidget);
    expect(find.text('+5.000,00 ₺'), findsOneWidget);
    expect(find.textContaining('10 Ocak 2027'), findsNothing);
  });

  testWidgets('nakit akışı tablosu son 6 ay', (tester) async {
    await open(tester);

    expect(find.text('Nakit akışı · son 6 ay'), findsOneWidget);
    expect(_text(tester, 'net-2026-11'), '27.499,50');
    expect(_text(tester, 'net-2026-10'), '-6.000,00');
    expect(_text(tester, 'net-2026-7'), '0,00');
    expect(_text(tester, 'net-2026-6'), '-1.000,00');
    // Mayıs 6 ayın dışında kalır.
    expect(find.byKey(const Key('net-2026-5')), findsNothing);
    expect(find.text('Gelir'), findsWidgets);
    expect(find.text('Gider'), findsWidgets);
  });

  testWidgets('ödeme yapılınca özet güncellenir', (tester) async {
    await open(tester);

    await tester.tap(find.widgetWithText(ListTile, 'Kira').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Ödendi olarak kaydet'));
    await tester.pumpAndSettle();

    // 15.000 ödendi: bu ay ödenecek 750, bakiye 245.498,50 − 15.000.
    expect(_text(tester, 'dash-due'), '750,00 ₺');
    expect(_text(tester, 'dash-balance'), '230.498,50 ₺');
    expect(_text(tester, 'net-2026-11'), '12.499,50');
  });

  testWidgets('boş hesapta özet sıfırlar ve yönlendirme gösterir', (
    tester,
  ) async {
    await pumpTestApp(tester, size: const Size(420, 2000));

    expect(_text(tester, 'dash-balance'), '0,00 ₺');
    expect(_text(tester, 'dash-due'), '0,00 ₺');
    expect(find.byKey(const Key('dash-overdue')), findsNothing);
    expect(find.text('Yaklaşan ödeme yok.'), findsOneWidget);
  });

  test('eksen adımı yuvarlak', () {
    expect(niceStep(7500), 10000);
    expect(niceStep(8625), 10000);
    expect(niceStep(1800), 2000);
    expect(niceStep(2400), 2500);
    expect(niceStep(4100), 5000);
    expect(niceStep(0.3), 0.5);
    expect(niceStep(0), 1);
  });

  test('aylık gelir/gider toplama', () {
    final f = MonthFlow.of(
      DateTime(2026, 11),
      [
        _tx('a', EntryKind.income, 100, DateTime(2026, 11, 1)),
        _tx('a', EntryKind.expense, 30, DateTime(2026, 11, 2)),
        _tx('a', EntryKind.expense, 5, DateTime(2026, 11, 3)),
      ].map(
        (d) => Transaction(
          id: 'x',
          accountId: d.accountId,
          type: d.type,
          amount: d.amount,
          occurredOn: d.occurredOn,
        ),
      ),
    );
    expect((f.income, f.expense, f.net), (100, 35, 65));
  });
}
