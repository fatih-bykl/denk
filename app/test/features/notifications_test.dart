import 'package:denk/app/routes.dart';
import 'package:denk/core/recurrence/recurrence.dart';
import 'package:denk/features/categories/domain/category.dart';
import 'package:denk/features/schedule/application/schedule_providers.dart';
import 'package:denk/features/schedule/domain/occurrence.dart';
import 'package:denk/features/schedule/domain/payment_schedule.dart';
import 'package:denk/features/transactions/domain/transaction.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/fake_data_repositories.dart';
import '../helpers/test_app.dart';

late FakeAccountsRepository accounts;
late FakeTransactionsRepository transactions;
late FakeScheduleRepository schedule;
late FakeNotificationService notifications;
late String cash;

Future<PaymentSchedule> _plan(
  String title,
  DateTime start, {
  int remind = 3,
  int amount = 1500000,
  Frequency frequency = Frequency.once,
  int? limit,
}) async {
  final id = await schedule.createSchedule(
    ScheduleDraft(
      title: title,
      flow: CashFlow.outflow,
      amount: amount,
      frequency: frequency,
      startDate: start,
      occurrenceLimit: limit,
      remindDaysBefore: remind,
    ),
  );
  final plan = schedule.schedules.firstWhere((s) => s.id == id);
  await syncSchedule(schedule, plan, testToday);
  return plan;
}

Future<void> _open(WidgetTester tester, {String? location}) => pumpTestApp(
  tester,
  accounts: accounts,
  transactions: transactions,
  schedule: schedule,
  notifications: notifications,
  location: location,
  size: const Size(420, 1400),
);

Future<void> _tap(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(initTestLocale);

  setUp(() {
    accounts = FakeAccountsRepository();
    cash = accounts.add('Nakit', opening: 5000000);
    transactions = FakeTransactionsRepository(accounts);
    schedule = FakeScheduleRepository(transactions);
    notifications = FakeNotificationService();
  });

  testWidgets('uygulama açılınca yaklaşan ödemeler için bildirim kurulur', (
    tester,
  ) async {
    await _plan('Kira', DateTime(2026, 11, 20)); // 3 gün önce → 17 Kas
    await _plan('Elektrik', DateTime(2026, 11, 7)); // 4 Kas geçti → vade günü
    await _plan('Su', DateTime(2026, 11, 4)); // gecikmiş → bildirim yok
    await _plan('Uzak', DateTime(2027, 3, 1)); // 60 günden sonra → yok
    await _open(tester);

    expect(notifications.scheduled.map((r) => (r.title, r.at)), [
      ('Ödeme: Elektrik', DateTime(2026, 11, 7, 9)),
      ('Ödeme: Kira', DateTime(2026, 11, 17, 9)),
    ]);
    expect(
      notifications.scheduled.last.body,
      '15.000,00 ₺ · 20 Kasım 2026 (3 gün sonra)',
    );
  });

  testWidgets('ödenen dönemin bildirimi kaldırılır', (tester) async {
    await _plan('Kira', DateTime(2026, 11, 20));
    await _open(tester);
    expect(notifications.scheduled, hasLength(1));

    // Özet ekranındaki yaklaşan ödemeler listesinden öde.
    await _tap(tester, find.widgetWithText(ListTile, 'Kira'));
    await _tap(tester, find.text('Ödendi olarak kaydet'));

    expect(transactions.items, hasLength(1));
    expect(notifications.scheduled, isEmpty);
  });

  testWidgets('ödeme işlemi silinince dönem ve bildirimi geri gelir', (
    tester,
  ) async {
    await _plan('Kira', DateTime(2026, 11, 20));
    await schedule.pay(
      schedule.occurrences.single.id,
      accountId: cash,
      amount: 1500000,
      paidOn: testToday,
    );
    await _open(tester, location: Routes.transactions);
    expect(notifications.scheduled, isEmpty);

    await _tap(tester, find.widgetWithText(ListTile, 'Kategorisiz'));
    await _tap(tester, find.text('İşlemi sil'));
    await _tap(tester, find.widgetWithText(FilledButton, 'Sil'));

    expect(schedule.occurrences.single.status, OccurrenceStatus.pending);
    expect(notifications.scheduled, hasLength(1));
  });

  testWidgets('Özet ekranında hatırlatma zamanı gelen ödeme uyarısı', (
    tester,
  ) async {
    await _plan('Elektrik', DateTime(2026, 11, 7), amount: 75000);
    await _plan('Kira', DateTime(2026, 11, 20));
    await _open(tester);

    final banner = find.byKey(const Key('due-soon'));
    expect(banner, findsOneWidget);
    expect(
      find.descendant(of: banner, matching: find.text('Elektrik')),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: banner,
        matching: find.text('2 gün sonra · 7 Kasım 2026'),
      ),
      findsOneWidget,
    );
    // Kira'nın hatırlatması 17 Kasım'da başlar; henüz uyarıda yok.
    expect(
      find.descendant(of: banner, matching: find.text('Kira')),
      findsNothing,
    );
  });

  testWidgets('hatırlatılacak ödeme yoksa uyarı görünmez', (tester) async {
    await _plan('Kira', DateTime(2026, 11, 20));
    await _open(tester);

    expect(find.byKey(const Key('due-soon')), findsNothing);
  });

  testWidgets('Ayarlar: bildirim durumu ve izin isteme', (tester) async {
    await _plan('Kira', DateTime(2026, 11, 20));
    notifications = FakeNotificationService(enabled: false);
    await _open(tester, location: Routes.settings);

    expect(find.text('Kapalı · ödeme hatırlatmaları gelmez'), findsOneWidget);
    await _tap(tester, find.text('İzin ver'));

    expect(notifications.permissionRequests, 1);
    expect(
      find.text('Açık · 1 hatırlatma kurulu · denemek için dokun'),
      findsOneWidget,
    );

    await _tap(tester, find.text('Bildirimler'));
    expect(notifications.testRequests, 1);
    expect(
      find.text('Deneme bildirimi 14:02 civarında gelecek.'),
      findsOneWidget,
    );
  });

  testWidgets('plan hatırlatma günü değişince bildirim zamanı güncellenir', (
    tester,
  ) async {
    await _plan('Kira', DateTime(2026, 11, 20));
    await _open(tester, location: Routes.schedules);
    expect(notifications.scheduled.single.at, DateTime(2026, 11, 17, 9));

    await _tap(tester, find.widgetWithText(ListTile, 'Kira'));
    await _tap(tester, find.text('3 gün önce'));
    await _tap(tester, find.text('Vade günü').last);
    await _tap(tester, find.text('Kaydet'));

    expect(notifications.scheduled.single.at, DateTime(2026, 11, 20, 9));
  });

  test('ödeme dışındaki işlem silinmesi takvimi bozmaz', () async {
    transactions.add(
      TransactionDraft(
        accountId: cash,
        type: EntryKind.expense,
        amount: 100,
        occurredOn: testToday,
      ),
    );
    await transactions.delete(transactions.items.single.id);
    expect(transactions.items, isEmpty);
  });
}
