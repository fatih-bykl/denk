// Yerel veritabanı testleri: şema kısıtları, tetikleyiciler, bakiye ve borç
// görünümleri, dönem eşitleme ve ödeme.

import 'dart:io';

import 'package:denk/core/database/app_database.dart';
import 'package:denk/core/date/dates.dart';
import 'package:denk/core/errors/data_failure.dart';
import 'package:denk/core/recurrence/recurrence.dart';
import 'package:denk/features/accounts/data/accounts_repository.dart';
import 'package:denk/features/categories/data/categories_repository.dart';
import 'package:denk/features/categories/domain/category.dart';
import 'package:denk/features/debts/data/debts_repository.dart';
import 'package:denk/features/debts/domain/debt.dart';
import 'package:denk/features/schedule/data/schedule_repository.dart';
import 'package:denk/features/schedule/domain/occurrence.dart';
import 'package:denk/features/schedule/domain/payment_schedule.dart';
import 'package:denk/features/transactions/data/transactions_repository.dart';
import 'package:denk/features/transactions/domain/transaction.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late AppDatabase db;
  late LocalAccountsRepository accounts;
  late LocalCategoriesRepository categories;
  late LocalTransactionsRepository transactions;
  late LocalScheduleRepository schedules;
  late LocalDebtsRepository debts;

  late String cash;
  late String market;
  late String salary;

  setUp(() async {
    db = AppDatabase.inMemory();
    accounts = LocalAccountsRepository(db);
    categories = LocalCategoriesRepository(db);
    transactions = LocalTransactionsRepository(db);
    schedules = LocalScheduleRepository(db);
    debts = LocalDebtsRepository(db);

    cash = (await accounts.fetchAll()).single.id;
    final all = await categories.fetchAll();
    market = all.firstWhere((c) => c.name == 'Market').id;
    salary = all.firstWhere((c) => c.name == 'Maaş').id;
  });

  tearDown(() => db.close());

  DateTime d(int y, int m, int day) => DateTime(y, m, day);

  TransactionDraft tx(
    EntryKind type,
    int amount, {
    String? category,
    String? debtId,
    String? account,
  }) => TransactionDraft(
    accountId: account ?? cash,
    type: type,
    amount: amount,
    occurredOn: d(2026, 11, 5),
    categoryId: category,
    debtId: debtId,
  );

  Matcher failsWith(String text) => throwsA(
    isA<DataFailure>().having((f) => f.message, 'message', contains(text)),
  );

  group('şema ve varsayılanlar', () {
    test('ilk açılışta Nakit hesabı ve 17 kategori kuruluyor', () async {
      final acc = await accounts.fetchAll();
      final cats = await categories.fetchAll();
      expect(acc.map((a) => a.name), ['Nakit']);
      expect(cats.where((c) => c.kind == EntryKind.expense), hasLength(12));
      expect(cats.where((c) => c.kind == EntryKind.income), hasLength(5));
    });

    test('dosya yeniden açılınca varsayılanlar tekrar eklenmiyor', () async {
      final dir = Directory.systemTemp.createTempSync('denk_test');
      addTearDown(() => dir.deleteSync(recursive: true));
      final path = '${dir.path}/denk.db';

      final first = AppDatabase.open(path);
      LocalAccountsRepository(first).create(name: 'Banka', openingBalance: 0);
      first.close();

      final second = AppDatabase.open(path);
      addTearDown(second.close);
      final names = (await LocalAccountsRepository(
        second,
      ).fetchAll()).map((a) => a.name);
      expect(names, ['Nakit', 'Banka']);
      expect((await LocalCategoriesRepository(second).fetchAll()).length, 17);
    });

    test('gider işlemine gelir kategorisi verilemiyor', () async {
      await expectLater(
        transactions.create(tx(EntryKind.expense, 100, category: salary)),
        failsWith('kategori'),
      );
      await expectLater(
        transactions.create(tx(EntryKind.expense, 100, category: market)),
        completes,
      );
    });

    test('işlem güncellenirken tür kategoriye uymazsa reddediliyor', () async {
      await transactions.create(tx(EntryKind.expense, 100, category: market));
      final id = (await transactions.fetchMonth(d(2026, 11, 1))).single.id;
      await expectLater(
        transactions.update(id, tx(EntryKind.income, 100, category: market)),
        failsWith('kategori'),
      );
    });

    test('sıfır tutar reddediliyor', () async {
      await expectLater(
        transactions.create(tx(EntryKind.expense, 0)),
        failsWith('geçerli değil'),
      );
    });

    test('aynı türde aynı adla iki kategori olamıyor', () async {
      await expectLater(
        categories.create(
          kind: EntryKind.expense,
          name: 'Market',
          icon: 'home',
        ),
        failsWith('zaten var'),
      );
      // Farklı türde aynı ad serbest ("Diğer" iki türde de var).
      await expectLater(
        categories.create(kind: EntryKind.income, name: 'Market', icon: 'home'),
        completes,
      );
    });

    test('kategori silinince işlemde yalnızca kategori boşalıyor', () async {
      await transactions.create(tx(EntryKind.expense, 100, category: market));
      db.execute('DELETE FROM categories WHERE id = ?', [market]);
      final t = (await transactions.fetchMonth(d(2026, 11, 1))).single;
      expect(t.categoryId, isNull);
      expect(t.amount, 100);
    });

    test('işlemi olan hesap silinemiyor', () async {
      await transactions.create(tx(EntryKind.expense, 100));
      expect(
        () => db.execute('DELETE FROM accounts WHERE id = ?', [cash]),
        throwsA(anything),
      );
    });

    test('olmayan hesaba işlem eklenemiyor', () async {
      await expectLater(
        transactions.create(tx(EntryKind.expense, 100, account: 'yok')),
        failsWith('kullanıldığı'),
      );
    });
  });

  group('hesap bakiyeleri', () {
    test('bakiye = açılış + gelir − gider', () async {
      await accounts.update(cash, name: 'Nakit', openingBalance: 100000);
      await transactions.create(tx(EntryKind.income, 25050));
      await transactions.create(tx(EntryKind.expense, 5000));
      expect((await accounts.fetchAll()).single.balance, 100000 + 25050 - 5000);
    });

    test(
      'bir hesabın işlemleri diğer hesabın bakiyesini etkilemiyor',
      () async {
        await accounts.create(name: 'Banka', openingBalance: -999);
        await transactions.create(tx(EntryKind.expense, 5000));
        final bank = (await accounts.fetchAll()).firstWhere(
          (a) => a.name == 'Banka',
        );
        expect(bank.balance, -999);
      },
    );

    test('arşivleme ve geri alma', () async {
      await accounts.setArchived(cash, archived: true);
      expect((await accounts.fetchAll()).single.archivedAt, isNotNull);
      await accounts.setArchived(cash, archived: false);
      expect((await accounts.fetchAll()).single.archivedAt, isNull);
    });
  });

  group('ödeme takvimi', () {
    late String rent;
    final dates = [d(2026, 12, 1), d(2027, 1, 1), d(2027, 2, 1)];

    Future<List<Occurrence>> occ([String? scheduleId]) async =>
        (await schedules.fetchOccurrences())
            .where((o) => o.scheduleId == (scheduleId ?? rent))
            .toList();

    setUp(() async {
      rent = await schedules.createSchedule(
        ScheduleDraft(
          title: 'Kira',
          flow: CashFlow.outflow,
          amount: 1500000,
          frequency: Frequency.monthly,
          startDate: d(2026, 12, 1),
          categoryId: market,
        ),
      );
      await schedules.syncOccurrences(rent, d(2026, 11, 1), dates);
    });

    test('eşitleme dönemleri oluşturuyor', () async {
      final rows = await occ();
      expect(rows, hasLength(3));
      expect(rows.every((o) => o.status == OccurrenceStatus.pending), isTrue);
      expect(rows.every((o) => o.amount == 1500000), isTrue);
      expect(rows.first.title, 'Kira');
      expect(rows.first.flow, CashFlow.outflow);
    });

    test('eşitleme tekrar çalışınca çoğaltmıyor', () async {
      await schedules.syncOccurrences(rent, d(2026, 11, 1), dates);
      expect(await occ(), hasLength(3));
    });

    test('ödeme işlem oluşturuyor ve dönemi kapatıyor', () async {
      final first = (await occ()).first;
      final txId = await schedules.pay(
        first.id,
        accountId: cash,
        amount: 1400000,
        paidOn: d(2026, 12, 2),
      );
      final paid = (await occ()).first;
      expect(paid.status, OccurrenceStatus.paid);
      expect(paid.transactionId, txId);
      expect(paid.amount, 1400000);

      final t = (await transactions.fetchMonth(d(2026, 12, 1))).single;
      expect(t.id, txId);
      expect(t.type, EntryKind.expense);
      expect(t.amount, 1400000);
      expect(t.note, 'Kira');
      expect(t.categoryId, market);
    });

    test('aynı dönem iki kez ödenemiyor', () async {
      final first = (await occ()).first;
      await schedules.pay(
        first.id,
        accountId: cash,
        amount: 1500000,
        paidOn: d(2026, 12, 1),
      );
      await expectLater(
        schedules.pay(
          first.id,
          accountId: cash,
          amount: 1500000,
          paidOn: d(2026, 12, 1),
        ),
        failsWith('zaten kapatılmış'),
      );
    });

    test('ödeme yarıda kalırsa hiçbir şey kaydedilmiyor', () async {
      final first = (await occ()).first;
      await expectLater(
        schedules.pay(
          first.id,
          accountId: 'olmayan-hesap',
          amount: 1500000,
          paidOn: d(2026, 12, 1),
        ),
        throwsA(isA<DataFailure>()),
      );
      expect((await occ()).first.status, OccurrenceStatus.pending);
      expect(await transactions.fetchMonth(d(2026, 12, 1)), isEmpty);
    });

    test('olmayan dönem ödenemiyor', () async {
      await expectLater(
        schedules.pay(
          'yok',
          accountId: cash,
          amount: 1,
          paidOn: d(2026, 12, 1),
        ),
        failsWith('bulunamadı'),
      );
    });

    test('kural değişince: ödenen korunur, fazla bekleyen silinir, tutar güncellenir', () async {
      final first = (await occ()).first;
      await schedules.pay(
        first.id,
        accountId: cash,
        amount: 1500000,
        paidOn: d(2026, 12, 1),
      );
      db.execute('UPDATE payment_schedules SET amount = 1600000 WHERE id = ?', [
        rent,
      ]);
      // Yeni kural: yalnızca Aralık ve Ocak.
      await schedules.syncOccurrences(
        rent,
        d(2026, 11, 1),
        dates.take(2).toList(),
      );

      final rows = await occ();
      expect(rows, hasLength(2));
      expect(rows[0].status, OccurrenceStatus.paid);
      expect(rows[0].amount, 1500000);
      expect(rows[1].status, OccurrenceStatus.pending);
      expect(rows[1].amount, 1600000);
    });

    test('başlangıçtan önceki bekleyen dönemlere dokunulmuyor', () async {
      await schedules.syncOccurrences(rent, d(2027, 1, 1), [d(2027, 3, 1)]);
      final due = (await occ()).map((o) => Dates.toDb(o.dueDate));
      expect(due, ['2026-12-01', '2027-03-01']);
    });

    test('ödeme işlemi silinince dönem yeniden bekliyor', () async {
      final first = (await occ()).first;
      final txId = await schedules.pay(
        first.id,
        accountId: cash,
        amount: 1500000,
        paidOn: d(2026, 12, 1),
      );
      await transactions.delete(txId);
      final reopened = (await occ()).first;
      expect(reopened.status, OccurrenceStatus.pending);
      expect(reopened.transactionId, isNull);
    });

    test('atlama ve geri alma', () async {
      final first = (await occ()).first;
      await schedules.setSkipped(first.id, skipped: true);
      expect((await occ()).first.status, OccurrenceStatus.skipped);
      // Atlanan dönem yeniden eşitlemede silinmiyor.
      await schedules.syncOccurrences(rent, d(2026, 11, 1), []);
      expect((await occ()).single.status, OccurrenceStatus.skipped);
      await schedules.setSkipped(first.id, skipped: false);
      expect((await occ()).single.status, OccurrenceStatus.pending);
    });

    test('gecikenler yalnızca ödenmemiş ve vadesi geçmiş dönemler', () async {
      final overdue = await schedules.fetchOverdue(d(2027, 1, 15));
      expect(overdue.map((o) => Dates.toDb(o.dueDate)), [
        '2026-12-01',
        '2027-01-01',
      ]);
    });

    test('tarih aralığıyla dönem sorgusu', () async {
      final rows = await schedules.fetchOccurrences(
        from: d(2027, 1, 1),
        to: d(2027, 2, 1),
      );
      expect(rows.map((o) => Dates.toDb(o.dueDate)), ['2027-01-01']);
    });

    test('plan güncelleme ve silme', () async {
      await schedules.updateSchedule(
        rent,
        ScheduleDraft(
          title: 'Ev kirası',
          flow: CashFlow.outflow,
          amount: 1500000,
          frequency: Frequency.monthly,
          startDate: d(2026, 12, 1),
          isActive: false,
        ),
      );
      final s = (await schedules.fetchSchedules()).single;
      expect(s.title, 'Ev kirası');
      expect(s.isActive, isFalse);

      await schedules.deleteSchedule(rent);
      expect(await schedules.fetchSchedules(), isEmpty);
      expect(await schedules.fetchOccurrences(), isEmpty);
    });
  });

  group('borçlar', () {
    late String debtId;
    late String scheduleId;

    Future<Debt> balance() async =>
        (await debts.fetchAll()).firstWhere((x) => x.id == debtId);

    setUp(() async {
      debtId = await debts.create(
        const DebtDraft(
          direction: DebtDirection.payable,
          counterparty: 'Ali',
          title: 'Telefon',
          totalAmount: 100000,
          installmentCount: 3,
        ),
      );
      scheduleId = await schedules.createSchedule(
        ScheduleDraft(
          title: 'Telefon taksiti',
          flow: CashFlow.outflow,
          amount: 33333,
          frequency: Frequency.monthly,
          startDate: d(2026, 12, 1),
          occurrenceLimit: 3,
          debtId: debtId,
        ),
      );
    });

    test('taksit tutarları dönem başına (son taksite kuruş farkı)', () async {
      await schedules.syncOccurrences(
        scheduleId,
        d(2026, 11, 1),
        [d(2026, 12, 1), d(2027, 1, 1), d(2027, 2, 1)],
        amounts: [33333, 33333, 33334],
      );
      final amounts = (await schedules.fetchOccurrences()).map((o) => o.amount);
      expect(amounts, [33333, 33333, 33334]);
    });

    test('tutar verilmezse plan tutarı kullanılıyor', () async {
      await schedules.syncOccurrences(scheduleId, d(2026, 11, 1), [
        d(2026, 12, 1),
        d(2027, 1, 1),
        d(2027, 2, 1),
      ]);
      final amounts = (await schedules.fetchOccurrences()).map((o) => o.amount);
      expect(amounts, [33333, 33333, 33333]);
    });

    test('ödeme yokken kalan = toplam, sonraki vade ilk taksit; '
        'ödeme yapılınca kalan azalıyor, vade ilerliyor', () async {
      await schedules.syncOccurrences(scheduleId, d(2026, 11, 1), [
        d(2026, 12, 1),
        d(2027, 1, 1),
      ]);
      var b = await balance();
      expect(b.paidAmount, 0);
      expect(b.remainingAmount, 100000);
      expect(b.scheduleId, scheduleId);
      expect(b.nextDueDate, d(2026, 12, 1));

      final first = (await schedules.fetchOccurrences()).first;
      await schedules.pay(
        first.id,
        accountId: cash,
        amount: 33333,
        paidOn: d(2026, 12, 1),
      );
      b = await balance();
      expect(b.paidAmount, 33333);
      expect(b.remainingAmount, 100000 - 33333);
      expect(b.nextDueDate, d(2027, 1, 1));
    });

    test('borca bağlı ters yönlü işlem ödenene sayılmıyor', () async {
      await transactions.create(tx(EntryKind.expense, 33333, debtId: debtId));
      await transactions.create(tx(EntryKind.income, 5000, debtId: debtId));
      expect((await balance()).paidAmount, 33333);
    });

    test('alacakta gelirler tahsilat sayılıyor', () async {
      final receivable = await debts.create(
        const DebtDraft(
          direction: DebtDirection.receivable,
          counterparty: 'Ayşe',
          title: 'Borç verdim',
          totalAmount: 50000,
        ),
      );
      await transactions.create(
        tx(EntryKind.income, 20000, debtId: receivable),
      );
      final b = (await debts.fetchAll()).firstWhere((x) => x.id == receivable);
      expect(b.paidAmount, 20000);
      expect(b.remainingAmount, 30000);
      expect(b.scheduleId, isNull);
      expect(b.nextDueDate, isNull);
    });

    test('borç silinince plan silinir, ödeme işlemi kalır', () async {
      await schedules.syncOccurrences(scheduleId, d(2026, 11, 1), [
        d(2026, 12, 1),
      ]);
      final first = (await schedules.fetchOccurrences()).first;
      await schedules.pay(
        first.id,
        accountId: cash,
        amount: 33333,
        paidOn: d(2026, 12, 1),
      );
      await debts.delete(debtId);

      expect(await schedules.fetchSchedules(), isEmpty);
      final t = (await transactions.fetchMonth(d(2026, 12, 1))).single;
      expect(t.amount, 33333);
      expect(t.debtId, isNull);
    });

    test('kapatma ve güncelleme', () async {
      await debts.setClosed(debtId, closed: true);
      expect((await balance()).closedAt, isNotNull);
      await debts.update(
        debtId,
        const DebtDraft(
          direction: DebtDirection.payable,
          counterparty: 'Ali',
          title: 'Telefon',
          totalAmount: 120000,
        ),
      );
      final b = await balance();
      expect(b.totalAmount, 120000);
      expect(b.installmentCount, isNull);
      expect(b.closedAt, isNotNull);
    });
  });

  test('tüm veriler silinince yalnızca varsayılanlar kalıyor', () async {
    await accounts.create(name: 'Banka', openingBalance: 500);
    await transactions.create(tx(EntryKind.expense, 100, category: market));
    final debtId = await debts.create(
      const DebtDraft(
        direction: DebtDirection.payable,
        counterparty: 'Ali',
        title: 'Telefon',
        totalAmount: 1000,
      ),
    );
    final planId = await schedules.createSchedule(
      ScheduleDraft(
        title: 'Taksit',
        flow: CashFlow.outflow,
        amount: 500,
        frequency: Frequency.monthly,
        startDate: d(2026, 12, 1),
        debtId: debtId,
      ),
    );
    await schedules.syncOccurrences(planId, d(2026, 11, 1), [d(2026, 12, 1)]);

    db.deleteAllData();

    expect((await accounts.fetchAll()).map((a) => a.name), ['Nakit']);
    expect((await accounts.fetchAll()).single.balance, 0);
    expect(await categories.fetchAll(), hasLength(17));
    expect(await transactions.fetchMonth(d(2026, 11, 1)), isEmpty);
    expect(await debts.fetchAll(), isEmpty);
    expect(await schedules.fetchSchedules(), isEmpty);
    expect(await schedules.fetchOccurrences(), isEmpty);
  });

  test('işlem sorguları: ay ve borç filtresi, yeniden eskiye', () async {
    await transactions.create(
      TransactionDraft(
        accountId: cash,
        type: EntryKind.expense,
        amount: 1,
        occurredOn: d(2026, 10, 31),
      ),
    );
    await transactions.create(tx(EntryKind.expense, 2));
    await transactions.create(
      TransactionDraft(
        accountId: cash,
        type: EntryKind.expense,
        amount: 3,
        occurredOn: d(2026, 11, 30),
        note: '  ',
      ),
    );
    final nov = await transactions.fetchMonth(d(2026, 11, 1));
    expect(nov.map((t) => t.amount), [3, 2]);
    expect(nov.first.note, isNull);
  });
}
