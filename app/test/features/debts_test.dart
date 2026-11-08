import 'package:denk/app/routes.dart';
import 'package:denk/core/date/dates.dart';
import 'package:denk/features/categories/domain/category.dart';
import 'package:denk/features/debts/application/debt_service.dart';
import 'package:denk/features/debts/domain/debt.dart';
import 'package:denk/features/schedule/application/schedule_providers.dart';
import 'package:denk/features/schedule/domain/occurrence.dart';
import 'package:denk/features/transactions/domain/transaction.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/fake_data_repositories.dart';
import '../helpers/test_app.dart';

late FakeAccountsRepository accounts;
late FakeTransactionsRepository transactions;
late FakeScheduleRepository schedule;
late FakeDebtsRepository debts;
late String cash;

DebtService _service() =>
    DebtService(debts: debts, schedules: schedule, today: testToday);

Future<Debt> _seed(
  String title, {
  DebtDirection direction = DebtDirection.payable,
  int total = 100000,
  int? installments,
  DateTime? firstInstallment,
  DateTime? dueDate,
}) async {
  await _service().save(
    draft: DebtDraft(
      direction: direction,
      counterparty: 'Banka',
      title: title,
      totalAmount: total,
      installmentCount: installments,
      dueDate: dueDate,
    ),
    firstInstallment: installments == null
        ? null
        : (firstInstallment ?? DateTime(2026, 11, 15)),
  );
  return debts.byTitle(title);
}

List<int> _amounts() => schedule.occurrences.map((o) => o.amount).toList();

Future<void> _open(WidgetTester tester, [String location = Routes.debts]) =>
    pumpTestApp(
      tester,
      accounts: accounts,
      transactions: transactions,
      schedule: schedule,
      debts: debts,
      location: location,
      size: const Size(420, 1100),
    );

Future<void> _tap(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

String _text(WidgetTester tester, String key) =>
    tester.widget<Text>(find.byKey(Key(key))).data!;

void main() {
  setUpAll(initTestLocale);

  setUp(() {
    accounts = FakeAccountsRepository();
    cash = accounts.add('Nakit', opening: 500000);
    transactions = FakeTransactionsRepository(accounts);
    schedule = FakeScheduleRepository(transactions);
    debts = FakeDebtsRepository(transactions, schedule);
  });

  test('taksit bölme: kuruş farkı son taksitte', () {
    expect(splitInstallments(100000, 3), [33333, 33333, 33334]);
    expect(splitInstallments(120000, 12), List.filled(12, 10000));
    expect(splitInstallments(5, 1), [5]);
    expect(splitInstallments(7, 3).reduce((a, b) => a + b), 7);
  });

  test('ay eklerken gün korunur', () {
    expect(
      Dates.addMonthsKeepDay(DateTime(2026, 1, 31), 1),
      DateTime(2026, 2, 28),
    );
    expect(
      Dates.addMonthsKeepDay(DateTime(2026, 11, 5), 1),
      DateTime(2026, 12, 5),
    );
    expect(
      Dates.addMonthsKeepDay(DateTime(2026, 11, 5), 12),
      DateTime(2027, 11, 5),
    );
  });

  testWidgets('taksitli borç formdan oluşturulur, taksitler takvime düşer', (
    tester,
  ) async {
    await _open(tester);

    await tester.tap(find.text('Kayıt ekle'));
    await tester.pumpAndSettle();
    await tester.enterText(formField('Kime borçlusun?'), 'X Bankası');
    await tester.enterText(formField('Açıklama'), 'İhtiyaç kredisi');
    await tester.enterText(formField('Toplam tutar'), '1.000');
    await _tap(tester, find.text('Taksitli'));
    await tester.enterText(formField('Taksit sayısı'), '3');
    await tester.pumpAndSettle();
    expect(
      _text(tester, 'installment-preview'),
      '2 × 333,33 ₺ + son taksit 333,34 ₺',
    );
    await _tap(tester, find.text('Kaydet'));

    final debt = debts.byTitle('İhtiyaç kredisi');
    expect(debt.installmentCount, 3);
    expect(debt.hasInstallments, isTrue);
    final plan = schedule.schedules.single;
    expect(plan.debtId, debt.id);
    expect(plan.title, 'İhtiyaç kredisi (X Bankası)');
    // İlk taksit varsayılan olarak bir ay sonraki aynı gün.
    expect(schedule.occurrences.map((o) => o.dueDate), [
      DateTime(2026, 12, 5),
      DateTime(2027, 1, 5),
      DateTime(2027, 2, 5),
    ]);
    expect(_amounts(), [33333, 33333, 33334]);
    expect(find.text('X Bankası'), findsOneWidget);
    expect(_text(tester, 'total-payable'), '1.000,00 ₺');
  });

  testWidgets('taksit ödendikçe kalan azalır (bitti kriteri)', (tester) async {
    final debt = await _seed('Taşıt kredisi', installments: 3);
    await schedule.pay(
      schedule.occurrences.first.id,
      accountId: cash,
      amount: 33333,
      paidOn: DateTime(2026, 11, 15),
    );
    await _open(tester);

    expect(transactions.items.single.debtId, debt.id);
    expect(
      find.descendant(
        of: find.byType(ListTile),
        matching: find.text('666,67 ₺'),
      ),
      findsOneWidget,
    );
    expect(_text(tester, 'total-payable'), '666,67 ₺');

    await _tap(tester, find.text('Banka'));
    expect(_text(tester, 'debt-remaining'), '666,67 ₺');
    expect(find.textContaining('sıradaki: 15 Aralık 2026'), findsOneWidget);
    expect(find.text('Taksitleri takvimde gör'), findsOneWidget);
  });

  testWidgets('takvimden ödenen taksit borç listesine hemen yansır', (
    tester,
  ) async {
    await _seed('Taşıt kredisi', installments: 3, firstInstallment: testToday);
    await _open(tester, Routes.schedule);

    await _tap(tester, find.widgetWithText(ListTile, 'Taşıt kredisi (Banka)'));
    await _tap(tester, find.text('Ödendi olarak kaydet'));
    await _tap(tester, find.text('Borçlar'));

    expect(
      find.descendant(
        of: find.byType(ListTile),
        matching: find.text('666,67 ₺'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('takvim açılınca taksit tutarları bozulmaz', (tester) async {
    await _seed('Taşıt kredisi', installments: 3);
    await _open(tester, Routes.schedule);

    // Ufuk eşitlemesi borç toplamını kullanır; son taksit 333,34 kalır.
    expect(_amounts(), [33333, 33333, 33334]);
  });

  testWidgets('taksitsiz borca ödeme eklenir, geçmişte görünür', (
    tester,
  ) async {
    final debt = await _seed('Elden borç', dueDate: DateTime(2026, 11, 1));
    await _open(tester);

    expect(find.text('Vade: 1 Kasım 2026'), findsOneWidget);
    await _tap(tester, find.text('Banka'));
    await _tap(tester, find.text('Ödeme ekle'));
    await tester.enterText(formField('Tutar'), '400');
    await _tap(tester, find.text('Ödemeyi kaydet'));

    final tx = transactions.items.single;
    expect(tx.debtId, debt.id);
    expect(tx.type, EntryKind.expense);
    expect(tx.amount, 40000);
    expect(tx.accountId, cash);
    expect(_text(tester, 'debt-remaining'), '600,00 ₺');
    expect(find.text('Ödemeler'), findsOneWidget);
  });

  testWidgets('alacak tahsilatı gelir olarak kaydedilir', (tester) async {
    await _seed(
      'Borç verdim',
      direction: DebtDirection.receivable,
      total: 50000,
    );
    await _open(tester);

    await _tap(tester, find.text('Alacaklarım'));
    expect(_text(tester, 'total-receivable'), '500,00 ₺');
    await _tap(tester, find.text('Banka'));
    await _tap(tester, find.text('Tahsilat ekle'));
    await _tap(tester, find.text('Tahsilatı kaydet'));

    expect(transactions.items.single.type, EntryKind.income);
    expect(_text(tester, 'debt-remaining'), '0,00 ₺');
    expect(find.textContaining('tamamı tahsil edildi'), findsOneWidget);
  });

  testWidgets('kapatılan taksitli borcun bekleyen taksitleri kalkar', (
    tester,
  ) async {
    await _seed('Taşıt kredisi', installments: 3);
    await _open(tester);

    await _tap(tester, find.text('Banka'));
    await _tap(tester, find.text('Kapat'));
    expect(schedule.schedules.single.isActive, isFalse);
    expect(schedule.occurrences, isEmpty);
    expect(find.text('Kapananlar (1)'), findsOneWidget);
    expect(_text(tester, 'total-payable'), '0,00 ₺');

    // Ayrıntı sayfası açık kalır; yeniden açma aynı sayfadan yapılır.
    expect(find.textContaining('Kapalı'), findsOneWidget);
    await _tap(tester, find.text('Yeniden aç'));
    expect(schedule.schedules.single.isActive, isTrue);
    expect(_amounts(), [33333, 33333, 33334]);
  });

  testWidgets('borç silinince planı silinir, ödeme işlemi kalır', (
    tester,
  ) async {
    await _seed('Taşıt kredisi', installments: 3);
    await schedule.pay(
      schedule.occurrences.first.id,
      accountId: cash,
      amount: 33333,
      paidOn: testToday,
    );
    await _open(tester);

    await _tap(tester, find.text('Banka'));
    await _tap(tester, find.text('Düzenle'));
    await _tap(tester, find.text('Kaydı sil'));
    await _tap(tester, find.widgetWithText(FilledButton, 'Sil'));

    expect(debts.rows, isEmpty);
    expect(schedule.schedules, isEmpty);
    expect(transactions.items.single.debtId, isNull);
    expect(find.text('Açık borcun yok.'), findsOneWidget);
  });

  testWidgets('taksit sayısı düzenlenince plan güncellenir', (tester) async {
    await _seed('Taşıt kredisi', installments: 3);
    await _open(tester);

    await _tap(tester, find.text('Banka'));
    await _tap(tester, find.text('Düzenle'));
    await tester.enterText(formField('Taksit sayısı'), '4');
    await _tap(tester, find.text('Kaydet'));

    expect(schedule.schedules.single.occurrenceLimit, 4);
    expect(_amounts(), [25000, 25000, 25000, 25000]);
    expect(schedule.occurrences.first.dueDate, DateTime(2026, 11, 15));
  });

  testWidgets('işlem düzenlenince borç bağı korunur', (tester) async {
    final debt = await _seed('Elden borç');
    transactions.add(
      TransactionDraft(
        accountId: cash,
        type: EntryKind.expense,
        amount: 10000,
        occurredOn: testToday,
        debtId: debt.id,
        note: 'Elden borç (Banka)',
      ),
    );
    await _open(tester, Routes.transactions);

    await _tap(tester, find.widgetWithText(ListTile, 'Kategorisiz'));
    await tester.enterText(formField('Tutar'), '150');
    await _tap(tester, find.text('Kaydet'));

    expect(transactions.items.single.amount, 15000);
    expect(transactions.items.single.debtId, debt.id);
    expect(debts.byTitle('Elden borç').remainingAmount, 85000);
  });

  test('ödenen taksitin dönemi ödendi durumunda', () async {
    await _seed('Taşıt kredisi', installments: 2);
    await schedule.pay(
      schedule.occurrences.first.id,
      accountId: cash,
      amount: 50000,
      paidOn: testToday,
    );
    expect(schedule.occurrences.first.status, OccurrenceStatus.paid);
    expect(debts.byTitle('Taşıt kredisi').nextDueDate, DateTime(2026, 12, 15));
  });
}
