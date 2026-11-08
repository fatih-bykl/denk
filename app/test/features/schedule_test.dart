import 'package:denk/app/routes.dart';
import 'package:denk/core/recurrence/recurrence.dart';
import 'package:denk/features/categories/domain/category.dart';
import 'package:denk/features/schedule/application/schedule_providers.dart';
import 'package:denk/features/schedule/domain/occurrence.dart';
import 'package:denk/features/schedule/domain/payment_schedule.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/fake_data_repositories.dart';
import '../helpers/test_app.dart';

late FakeAccountsRepository accounts;
late FakeCategoriesRepository categories;
late FakeTransactionsRepository transactions;
late FakeScheduleRepository schedule;
late String cash;

Future<PaymentSchedule> _seedPlan(
  String title,
  int amount, {
  Frequency frequency = Frequency.monthly,
  DateTime? start,
  int? limit,
  CashFlow flow = CashFlow.outflow,
}) async {
  final id = await schedule.createSchedule(
    ScheduleDraft(
      title: title,
      flow: flow,
      amount: amount,
      frequency: frequency,
      startDate: start ?? testToday,
      occurrenceLimit: limit,
      categoryId: categories.byName('Kira').id,
    ),
  );
  final plan = schedule.schedules.firstWhere((s) => s.id == id);
  await syncSchedule(schedule, plan, testToday);
  return plan;
}

Future<void> _open(WidgetTester tester, [String location = Routes.schedule]) =>
    pumpTestApp(
      tester,
      accounts: accounts,
      categories: categories,
      transactions: transactions,
      schedule: schedule,
      location: location,
      size: const Size(420, 1100),
    );

Future<void> _tap(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

Finder _tile(String title) => find.widgetWithText(ListTile, title);

String _due(WidgetTester tester) =>
    tester.widget<Text>(find.byKey(const Key('due-this-month'))).data!;

void main() {
  setUpAll(initTestLocale);

  setUp(() {
    accounts = FakeAccountsRepository();
    cash = accounts.add('Nakit', opening: 5000000);
    categories = FakeCategoriesRepository()
      ..add(EntryKind.expense, 'Kira', icon: 'home')
      ..add(EntryKind.income, 'Maaş', icon: 'payments');
    transactions = FakeTransactionsRepository(accounts);
    schedule = FakeScheduleRepository(transactions);
  });

  testWidgets('boş takvim', (tester) async {
    await _open(tester);

    expect(find.text('Bu gün için ödeme yok.'), findsOneWidget);
    expect(_due(tester), '0,00 ₺');
  });

  testWidgets('3 taksitli aylık plan formdan oluşturulur', (tester) async {
    await _open(tester);

    await tester.tap(find.text('Plan ekle'));
    await tester.pumpAndSettle();
    await tester.enterText(formField('Başlık'), 'Telefon taksiti');
    await tester.enterText(formField('Tutar (her dönem)'), '1.250');
    await _tap(tester, find.text('Taksit'));
    await tester.enterText(formField('Toplam taksit / dönem sayısı'), '3');
    await _tap(tester, find.text('Kaydet'));

    final plan = schedule.byTitle('Telefon taksiti');
    expect(plan.frequency, Frequency.monthly);
    expect(plan.occurrenceLimit, 3);
    expect(plan.startDate, testToday);
    expect(schedule.occurrences.map((o) => o.dueDate), [
      DateTime(2026, 11, 5),
      DateTime(2026, 12, 5),
      DateTime(2027, 1, 5),
    ]);
    // Bugün seçili; dönem listede ve ay toplamında görünür.
    expect(_tile('Telefon taksiti'), findsOneWidget);
    expect(_due(tester), '1.250,00 ₺');
  });

  testWidgets('"Tarihte" bitişinin varsayılanı bir yıl sonraki aynı gün', (
    tester,
  ) async {
    await _open(tester);

    await tester.tap(find.text('Plan ekle'));
    await tester.pumpAndSettle();
    await _tap(tester, find.text('Tarihte'));

    expect(find.text('5 Kasım 2027'), findsOneWidget);
  });

  testWidgets('süresiz plan 12 ay ileriye kadar dönem üretir', (tester) async {
    await _seedPlan('Kira', 1500000);
    await _open(tester);

    final dates = schedule.occurrences.map((o) => o.dueDate).toList();
    expect(dates.length, 13);
    expect(dates.first, DateTime(2026, 11, 5));
    expect(dates.last, DateTime(2027, 11, 5));
  });

  testWidgets('ödendi işaretlenince işlem oluşur ve bakiye düşer', (
    tester,
  ) async {
    await _seedPlan('Kira', 1500000, limit: 2);
    await _open(tester);

    await _tap(tester, _tile('Kira'));
    await tester.enterText(formField('Tutar'), '14.500');
    await _tap(tester, find.text('Ödendi olarak kaydet'));

    final tx = transactions.items.single;
    expect(tx.amount, 1450000);
    expect(tx.type, EntryKind.expense);
    expect(tx.accountId, cash);
    expect(tx.categoryId, categories.byName('Kira').id);
    expect(tx.occurredOn, testToday);
    expect(tx.note, 'Kira');
    expect(schedule.occurrences.first.status, OccurrenceStatus.paid);
    expect(find.text('Ödendi'), findsOneWidget);
    // Kasım'da ödenecek kalmadı.
    expect(_due(tester), '0,00 ₺');

    await _open(tester, Routes.accounts);
    expect(find.text('35.500,00 ₺'), findsWidgets);
  });

  testWidgets('tahsilat planı gelir işlemi oluşturur', (tester) async {
    await _seedPlan('Kira geliri', 800000, flow: CashFlow.inflow, limit: 1);
    await _open(tester);

    await _tap(tester, _tile('Kira geliri'));
    await _tap(tester, find.text('Tahsil edildi olarak kaydet'));

    expect(transactions.items.single.type, EntryKind.income);
    expect(find.text('Tahsil edildi'), findsOneWidget);
  });

  testWidgets('ödeme geri alınınca işlem silinir, dönem yeniden bekler', (
    tester,
  ) async {
    await _seedPlan('Kira', 1500000, limit: 1);
    await schedule.pay(
      schedule.occurrences.single.id,
      accountId: cash,
      amount: 1500000,
      paidOn: testToday,
    );
    await _open(tester);

    await _tap(tester, _tile('Kira'));
    await _tap(tester, find.text('Ödemeyi geri al'));

    expect(transactions.items, isEmpty);
    expect(schedule.occurrences.single.status, OccurrenceStatus.pending);
    expect(find.text('Bekliyor'), findsOneWidget);
  });

  testWidgets('dönem atlanır ve atlama geri alınır', (tester) async {
    await _seedPlan('Spor salonu', 90000, limit: 1);
    await _open(tester);

    await _tap(tester, _tile('Spor salonu'));
    await _tap(tester, find.text('Bu dönemi atla'));
    expect(find.text('Atlandı'), findsOneWidget);
    expect(_due(tester), '0,00 ₺');
    expect(transactions.items, isEmpty);

    await _tap(tester, _tile('Spor salonu'));
    await _tap(tester, find.text('Atlamayı geri al'));
    expect(find.text('Bekliyor'), findsOneWidget);
  });

  testWidgets('geçmiş aydan kalan ödenmemiş dönem gecikmiş görünür', (
    tester,
  ) async {
    final plan = await _seedPlan('Elektrik', 45000, limit: 1);
    schedule.occurrences.add(
      Occurrence(
        id: 'eski',
        scheduleId: plan.id,
        dueDate: DateTime(2026, 10, 20),
        amount: 52000,
        status: OccurrenceStatus.pending,
        title: 'Elektrik',
        flow: CashFlow.outflow,
      ),
    );
    await _open(tester);

    expect(find.text('Gecikmiş ödemeler'), findsOneWidget);
    expect(find.text('1 gecikmiş'), findsOneWidget);
    expect(find.textContaining('20 Ekim 2026 · Gecikmiş'), findsOneWidget);
  });

  testWidgets('plan tutarı değişince bekleyen dönemler güncellenir', (
    tester,
  ) async {
    await _seedPlan('Kira', 1500000, limit: 3);
    await schedule.pay(
      schedule.occurrences.first.id,
      accountId: cash,
      amount: 1500000,
      paidOn: testToday,
    );
    await _open(tester, Routes.schedules);

    expect(find.textContaining('Aylık'), findsOneWidget);
    await _tap(tester, _tile('Kira'));
    expect(find.text('Planı düzenle'), findsOneWidget);
    await tester.enterText(formField('Tutar (her dönem)'), '16.000');
    await _tap(tester, find.text('Kaydet'));

    final amounts = schedule.occurrences.map((o) => o.amount).toList();
    expect(amounts, [1500000, 1600000, 1600000]);
  });

  testWidgets('plan silinir, ödemenin işlem kaydı kalır', (tester) async {
    await _seedPlan('Kira', 1500000, limit: 2);
    await schedule.pay(
      schedule.occurrences.first.id,
      accountId: cash,
      amount: 1500000,
      paidOn: testToday,
    );
    await _open(tester, Routes.schedules);

    await _tap(tester, _tile('Kira'));
    await _tap(tester, find.text('Planı sil'));
    await _tap(tester, find.widgetWithText(FilledButton, 'Sil'));

    expect(schedule.schedules, isEmpty);
    expect(schedule.occurrences, isEmpty);
    expect(transactions.items.length, 1);
    expect(find.textContaining('Henüz ödeme planı yok'), findsOneWidget);
  });
}
