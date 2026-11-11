import 'package:denk/app/routes.dart';
import 'package:denk/core/errors/data_failure.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/fake_data_repositories.dart';
import '../helpers/test_app.dart';

const _offline = DataFailure(
  'Sunucuya ulaşılamadı. İnternet bağlantını kontrol et.',
);

late FakeAccountsRepository accounts;
late FakeTransactionsRepository transactions;
late FakeScheduleRepository schedule;
late FakeDebtsRepository debts;

Future<void> _open(WidgetTester tester, String location) => pumpTestApp(
  tester,
  accounts: accounts,
  transactions: transactions,
  schedule: schedule,
  debts: debts,
  location: location,
  size: const Size(420, 1400),
);

void main() {
  setUpAll(initTestLocale);

  setUp(() {
    accounts = FakeAccountsRepository();
    transactions = FakeTransactionsRepository(accounts);
    schedule = FakeScheduleRepository(transactions);
    debts = FakeDebtsRepository(transactions, schedule);
  });

  // Her sekme bağlantı yokken Türkçe mesaj ve "Tekrar dene" gösterir,
  // bağlantı gelince "Tekrar dene" ile veriyi yükler.
  final cases = <(String, String, void Function(), String)>[
    (
      'İşlemler',
      Routes.transactions,
      () => transactions.fetchFailure = _offline,
      'Bu ay işlem yok. "İşlem ekle" ile ilk kaydını gir.',
    ),
    (
      'Takvim',
      Routes.schedule,
      () => schedule.fetchFailure = _offline,
      'Bu gün için ödeme yok.',
    ),
    (
      'Borçlar',
      Routes.debts,
      () => debts.fetchFailure = _offline,
      'Açık borcun yok.',
    ),
    (
      'Hesaplar',
      Routes.accounts,
      () => accounts.fetchFailure = _offline,
      'Aktif hesap yok. "Hesap ekle" ile bir hesap oluştur.',
    ),
  ];

  for (final (name, location, breakIt, emptyText) in cases) {
    testWidgets('$name: bağlantı yokken hata ve tekrar dene', (tester) async {
      breakIt();
      await _open(tester, location);

      expect(find.text(_offline.message), findsOneWidget);
      expect(find.text('Tekrar dene'), findsOneWidget);

      accounts.fetchFailure = null;
      transactions.fetchFailure = null;
      schedule.fetchFailure = null;
      debts.fetchFailure = null;
      await tester.tap(find.text('Tekrar dene'));
      await tester.pumpAndSettle();

      expect(find.text(_offline.message), findsNothing);
      expect(find.text(emptyText), findsOneWidget);
    });
  }

  testWidgets('Özet: bölüm yüklenemezse yalnız o bölümde mesaj', (
    tester,
  ) async {
    transactions.fetchFailure = _offline;
    await _open(tester, Routes.dashboard);

    // İşleme dayanan iki kart (ay özeti, nakit akışı) yüklenemedi; diğerleri çalışıyor.
    expect(find.text('Yüklenemedi. Aşağı çekerek yenile.'), findsNWidgets(2));
    expect(find.byKey(const Key('dash-balance')), findsOneWidget);
    expect(find.byKey(const Key('dash-due')), findsOneWidget);
  });

  testWidgets('hesap yokken işlem formu yol gösterir', (tester) async {
    await _open(tester, Routes.transactions);

    await tester.tap(find.text('İşlem ekle'));
    await tester.pumpAndSettle();

    expect(
      find.text('Önce Ayarlar → Hesaplar bölümünden bir hesap ekle.'),
      findsOneWidget,
    );
  });
}
