// Özet ekranındaki ay özeti: gelir/gider kartları, kategori halkası, tasarruf oranı
// ve kategori listesi.

import 'package:denk/features/categories/domain/category.dart';
import 'package:denk/features/dashboard/application/category_breakdown.dart';
import 'package:denk/features/dashboard/presentation/category_donut.dart';
import 'package:denk/features/transactions/domain/transaction.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/fake_data_repositories.dart';
import '../helpers/test_app.dart';

Transaction _t(EntryKind type, int kurus, String? category) => Transaction(
  id: 't$kurus',
  accountId: 'a',
  categoryId: category,
  type: type,
  amount: kurus,
  occurredOn: DateTime(2026, 11, 1),
);

Category _c(String id, String name) =>
    Category(id: id, kind: EntryKind.expense, name: name);

void main() {
  group('kategori dağılımı', () {
    test('kategoriye göre toplar, büyükten küçüğe sıralar, payı hesaplar', () {
      final data = breakdownOf(
        [
          _t(EntryKind.expense, 6000, 'm'),
          _t(EntryKind.expense, 3000, 'k'),
          _t(EntryKind.expense, 1000, 'm'),
          _t(EntryKind.income, 99999, null),
        ],
        EntryKind.expense,
        [_c('m', 'Market'), _c('k', 'Kira')],
      );
      expect(data.total, 10000);
      expect(data.items.map((i) => i.name), ['Market', 'Kira']);
      expect(data.items.map((i) => i.amount), [7000, 3000]);
      expect(data.items.first.share, closeTo(0.7, 1e-9));
    });

    test(
      'kategorisiz ve silinmiş kategorili işlemler "Kategorisiz" sayılır',
      () {
        final data = breakdownOf(
          [
            _t(EntryKind.expense, 500, null),
            _t(EntryKind.expense, 700, 'silinmis'),
          ],
          EntryKind.expense,
          const [],
        );
        expect(data.items.single.name, 'Kategorisiz');
        expect(data.items.single.amount, 1200);
      },
    );

    test(
      '6 kategoriden fazlası gri "Diğer" dilimine toplanır, renk başa dönmez',
      () {
        final cats = [for (var i = 0; i < 8; i++) _c('c$i', 'K$i')];
        final data = breakdownOf(
          [
            for (var i = 0; i < 8; i++)
              _t(EntryKind.expense, (8 - i) * 100, 'c$i'),
          ],
          EntryKind.expense,
          cats,
        );
        final slices = slicesOf(data, Brightness.dark);
        expect(slices, hasLength(7));
        expect(slices.last.label, 'Diğer');
        expect(slices.last.amount, 200 + 100);
        expect(slices.last.color, ChartPalette.other(Brightness.dark));
        // İlk altı dilimin renkleri birbirinden farklı.
        expect(slices.take(6).map((s) => s.color).toSet(), hasLength(6));
        // Listede 7. ve 8. kategori de griyle işaretlenir.
        expect(
          colorOfItem(6, Brightness.dark),
          ChartPalette.other(Brightness.dark),
        );
      },
    );

    test('tek kategori kalırsa gri dilim kendi adıyla görünür', () {
      final cats = [for (var i = 0; i < 7; i++) _c('c$i', 'K$i')];
      final data = breakdownOf(
        [
          for (var i = 0; i < 7; i++)
            _t(EntryKind.expense, (7 - i) * 100, 'c$i'),
        ],
        EntryKind.expense,
        cats,
      );
      expect(slicesOf(data, Brightness.light).last.label, 'K6');
    });

    test('yüzde biçimi', () {
      expect(percent(0.2449), '%24');
      expect(percent(0.005), '%0,5');
      expect(percent(0), '%0');
    });
  });

  group('özet ekranı', () {
    setUpAll(initTestLocale);

    late FakeAccountsRepository accounts;
    late FakeCategoriesRepository categories;
    late FakeTransactionsRepository transactions;

    setUp(() {
      accounts = FakeAccountsRepository();
      final cash = accounts.add('Nakit', opening: 0);
      categories = FakeCategoriesRepository()
        ..add(EntryKind.expense, 'Kira', icon: 'home')
        ..add(EntryKind.expense, 'Market', icon: 'shopping_cart')
        ..add(EntryKind.income, 'Maaş', icon: 'payments');
      transactions = FakeTransactionsRepository(accounts);
      void add(EntryKind k, int kurus, String cat, DateTime day) =>
          transactions.add(
            TransactionDraft(
              accountId: cash,
              type: k,
              amount: kurus,
              occurredOn: day,
              categoryId: categories.byName(cat).id,
            ),
          );
      // Kasım: gelir 10.000, gider 6.000 + 2.000 → kalan 2.000, tasarruf %20.
      add(EntryKind.income, 1000000, 'Maaş', DateTime(2026, 11, 1));
      add(EntryKind.expense, 600000, 'Kira', DateTime(2026, 11, 2));
      add(EntryKind.expense, 200000, 'Market', DateTime(2026, 11, 3));
      // Ekim: gider 4.000 → Kasım gideri %100 arttı.
      add(EntryKind.expense, 400000, 'Market', DateTime(2026, 10, 5));
    });

    Future<void> open(WidgetTester tester) => pumpTestApp(
      tester,
      accounts: accounts,
      categories: categories,
      transactions: transactions,
      size: const Size(420, 2600),
    );

    String text(WidgetTester tester, String key) =>
        tester.widget<Text>(find.byKey(Key(key))).data!;

    testWidgets('ay özeti rakamları elle hesaplananla aynı', (tester) async {
      await open(tester);

      expect(text(tester, 'overview-month'), 'Kasım 2026');
      expect(text(tester, 'overview-net'), '2.000,00 ₺');
      expect(text(tester, 'donut-center-label'), 'Toplam gider');
      expect(text(tester, 'donut-center-amount'), '8.000,00 ₺');
      expect(text(tester, 'savings-rate'), '%20');
      expect(find.text('%100 geçen aya göre'), findsOneWidget);
      expect(find.byType(PieChart), findsOneWidget);
      // Liste: Kira %75, Market %25.
      expect(find.text('Gider kategorileri'), findsOneWidget);
      expect(
        find.descendant(
          of: find.byKey(const Key('share-Kira')),
          matching: find.text('%75'),
        ),
        findsOneWidget,
      );
    });

    testWidgets('Gelir kartına dokununca halka gelirleri gösterir', (
      tester,
    ) async {
      await open(tester);

      await tester.tap(find.byKey(const Key('tile-income')));
      await tester.pumpAndSettle();

      expect(text(tester, 'donut-center-label'), 'Toplam gelir');
      expect(text(tester, 'donut-center-amount'), '10.000,00 ₺');
      expect(find.text('Gelir kategorileri'), findsOneWidget);
      expect(find.byKey(const Key('share-Maaş')), findsOneWidget);
    });

    testWidgets('önceki aya geçilir; içinde bulunulan aydan ileri gidilmez', (
      tester,
    ) async {
      await open(tester);
      final next = find.ancestor(
        of: find.byTooltip('Sonraki ay'),
        matching: find.byType(IconButton),
      );
      expect(tester.widget<IconButton>(next).onPressed, isNull);

      await tester.tap(find.byTooltip('Önceki ay'));
      await tester.pumpAndSettle();

      expect(text(tester, 'overview-month'), 'Ekim 2026');
      expect(text(tester, 'donut-center-amount'), '4.000,00 ₺');
      // Ekim'de gelir yok: tasarruf halkası gösterilmez.
      expect(find.byKey(const Key('savings-rate')), findsNothing);
      expect(tester.widget<IconButton>(next).onPressed, isNotNull);

      await tester.tap(find.byTooltip('Önceki ay'));
      await tester.pumpAndSettle();
      expect(find.text('Bu ay henüz gider yok.'), findsOneWidget);
      expect(find.byType(PieChart), findsNothing);
    });

    testWidgets('dilime dokununca ortada o kategori görünür', (tester) async {
      await open(tester);

      // Halkanın sağ yarısı en büyük dilim (Kira, %75; saat 12'den başlar).
      final chart = tester.getRect(find.byType(PieChart));
      // Halka, grafiğin yüksekliğine göre çizilir: iç boşluk %25, kalınlık %15.
      final tapAt = chart.center + Offset(chart.height * 0.32, 0);
      await tester.tapAt(tapAt);
      await tester.pumpAndSettle();
      expect(text(tester, 'donut-center-label'), 'Kira');
      expect(text(tester, 'donut-center-amount'), '6.000,00 ₺');

      await tester.tapAt(tapAt);
      await tester.pumpAndSettle();
      expect(text(tester, 'donut-center-label'), 'Toplam gider');
    });
  });
}
