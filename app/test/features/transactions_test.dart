import 'package:denk/app/routes.dart';
import 'package:denk/core/date/dates.dart';
import 'package:denk/features/categories/domain/category.dart';
import 'package:denk/features/transactions/domain/transaction.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/fake_data_repositories.dart';
import '../helpers/test_app.dart';

late FakeAccountsRepository accounts;
late FakeCategoriesRepository categories;
late FakeTransactionsRepository transactions;
late String cash;
late String bank;

String _cat(String name) => categories.byName(name).id;

TransactionDraft _draft(
  String accountId,
  EntryKind type,
  int amount,
  DateTime day, {
  String? category,
  String? note,
}) => TransactionDraft(
  accountId: accountId,
  type: type,
  amount: amount,
  occurredOn: day,
  categoryId: category == null ? null : _cat(category),
  note: note,
);

Finder _inTile(String text) =>
    find.descendant(of: find.byType(ListTile), matching: find.text(text));

String _text(WidgetTester tester, String key) =>
    tester.widget<Text>(find.byKey(Key(key))).data!;

Future<void> _openForm(WidgetTester tester, String tileTitle) async {
  await tester.tap(find.widgetWithText(ListTile, tileTitle).first);
  await tester.pumpAndSettle();
}

/// Filtre çubuğu yatay kayar; dar ekranda çip görünür alana getirilir.
Future<void> _tapChip(WidgetTester tester, String label) async {
  await tester.ensureVisible(find.text(label));
  await tester.pumpAndSettle();
  await tester.tap(find.text(label));
  await tester.pumpAndSettle();
}

Future<void> _save(WidgetTester tester) async {
  await tester.tap(find.text('Kaydet'));
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(initTestLocale);

  setUp(() {
    accounts = FakeAccountsRepository();
    cash = accounts.add('Nakit', opening: 100000);
    bank = accounts.add('Banka', opening: 500000);
    categories = FakeCategoriesRepository()
      ..add(EntryKind.expense, 'Market', icon: 'shopping_cart')
      ..add(EntryKind.expense, 'Kira', icon: 'home')
      ..add(EntryKind.income, 'Maaş', icon: 'payments');
    transactions = FakeTransactionsRepository(accounts);
  });

  Future<void> open(
    WidgetTester tester, [
    String location = Routes.transactions,
  ]) => pumpTestApp(
    tester,
    accounts: accounts,
    categories: categories,
    transactions: transactions,
    location: location,
  );

  testWidgets('boş ayda yönlendirme mesajı gösterilir', (tester) async {
    await open(tester);

    expect(_text(tester, 'month-label'), 'Kasım 2026');
    expect(find.textContaining('Bu ay işlem yok'), findsOneWidget);
  });

  testWidgets('gider eklenir, listede ve hesap bakiyesinde görünür', (
    tester,
  ) async {
    await open(tester);

    await tester.tap(find.text('İşlem ekle'));
    await tester.pumpAndSettle();
    await tester.enterText(formField('Tutar'), '250,75');
    await tester.tap(
      find.widgetWithText(DropdownButtonFormField<String?>, 'Kategorisiz'),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Market').last);
    await tester.pumpAndSettle();
    await tester.enterText(
      formField('Not (isteğe bağlı)'),
      'Haftalık alışveriş',
    );
    await _save(tester);

    final saved = transactions.items.single;
    expect(saved.type, EntryKind.expense);
    expect(saved.amount, 25075);
    expect(saved.accountId, cash);
    expect(saved.categoryId, _cat('Market'));
    expect(saved.occurredOn, testToday);
    expect(find.text('Bugün'), findsOneWidget);
    expect(_inTile('-250,75 ₺'), findsOneWidget);
    expect(find.textContaining('Haftalık alışveriş'), findsOneWidget);
    expect(_text(tester, 'sum-expense'), '250,75 ₺');
    expect(_text(tester, 'sum-net'), '-250,75 ₺');

    // Bitti kriteri: bakiye işlemi yansıtıyor (1.000,00 − 250,75).
    await open(tester, Routes.accounts);
    expect(find.text('749,25 ₺'), findsOneWidget);
  });

  testWidgets('gelir seçilince yalnızca gelir kategorileri listelenir', (
    tester,
  ) async {
    await open(tester);

    await tester.tap(find.text('İşlem ekle'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Gelir').last);
    await tester.pumpAndSettle();
    await tester.tap(
      find.widgetWithText(DropdownButtonFormField<String?>, 'Kategorisiz'),
    );
    await tester.pumpAndSettle();

    expect(find.text('Maaş'), findsWidgets);
    expect(find.text('Market'), findsNothing);
  });

  testWidgets('tutar girilmeden kaydedilmez', (tester) async {
    await open(tester);

    await tester.tap(find.text('İşlem ekle'));
    await tester.pumpAndSettle();
    await _save(tester);

    expect(find.text('Tutar gerekli.'), findsOneWidget);
    expect(transactions.items, isEmpty);
  });

  group('kayıtlı işlemlerle', () {
    setUp(() {
      transactions
        ..add(
          _draft(cash, EntryKind.expense, 30000, testToday, category: 'Market'),
        )
        ..add(
          _draft(
            bank,
            EntryKind.income,
            2000000,
            DateTime(2026, 11, 1),
            category: 'Maaş',
          ),
        )
        ..add(
          _draft(
            bank,
            EntryKind.expense,
            1500000,
            DateTime(2026, 11, 4),
            category: 'Kira',
          ),
        )
        ..add(
          _draft(
            cash,
            EntryKind.expense,
            9900,
            DateTime(2026, 10, 20),
            category: 'Market',
          ),
        );
    });

    testWidgets('ay özeti ve günlere göre gruplama', (tester) async {
      await open(tester);

      expect(_text(tester, 'sum-income'), '20.000,00 ₺');
      expect(_text(tester, 'sum-expense'), '15.300,00 ₺');
      expect(_text(tester, 'sum-net'), '4.700,00 ₺');
      expect(find.text('Bugün'), findsOneWidget);
      expect(find.text('Dün'), findsOneWidget);
      expect(find.text('1 Kasım Pazar'), findsOneWidget);
      // Ekim işlemi bu ayda görünmez.
      expect(find.text('-99,00 ₺'), findsNothing);
    });

    testWidgets('önceki aya geçilir', (tester) async {
      await open(tester);

      await tester.tap(find.byTooltip('Önceki ay'));
      await tester.pumpAndSettle();

      expect(_text(tester, 'month-label'), 'Ekim 2026');
      expect(_inTile('-99,00 ₺'), findsOneWidget);
      expect(_text(tester, 'sum-expense'), '99,00 ₺');
    });

    testWidgets('tür, hesap ve kategori filtreleri', (tester) async {
      await open(tester);

      await tester.tap(find.widgetWithText(ChoiceChip, 'Gelir'));
      await tester.pumpAndSettle();
      expect(_inTile('+20.000,00 ₺'), findsOneWidget);
      expect(_inTile('-300,00 ₺'), findsNothing);
      expect(_text(tester, 'sum-expense'), '0,00 ₺');

      await tester.tap(find.widgetWithText(ChoiceChip, 'Tümü'));
      await tester.pumpAndSettle();
      await _tapChip(tester, 'Hesap: Tümü');
      await tester.pumpAndSettle();
      await tester.tap(find.text('Nakit').last);
      await tester.pumpAndSettle();
      expect(_inTile('-300,00 ₺'), findsOneWidget);
      expect(_inTile('-15.000,00 ₺'), findsNothing);

      await _tapChip(tester, 'Hesap: Nakit');
      await tester.pumpAndSettle();
      await tester.tap(find.text('Tümü').last);
      await tester.pumpAndSettle();
      await _tapChip(tester, 'Kategori: Tümü');
      await tester.pumpAndSettle();
      await tester.tap(find.text('Kira').last);
      await tester.pumpAndSettle();
      expect(_inTile('-15.000,00 ₺'), findsOneWidget);
      expect(_inTile('-300,00 ₺'), findsNothing);
    });

    testWidgets('işlem düzenlenir ve bakiye güncellenir', (tester) async {
      await open(tester);

      await _openForm(tester, 'Market');
      expect(find.text('İşlemi düzenle'), findsOneWidget);
      await tester.enterText(formField('Tutar'), '450');
      await _save(tester);

      expect(find.text('-450,00 ₺'), findsOneWidget);
      expect(transactions.items.first.amount, 45000);

      // Nakit: 1.000 − 450 (Kasım) − 99 (Ekim)
      await open(tester, Routes.accounts);
      expect(find.text('451,00 ₺'), findsOneWidget);
    });

    testWidgets('işlem onayla silinir, vazgeçilirse silinmez', (tester) async {
      await open(tester);

      await _openForm(tester, 'Kira');
      await tester.tap(find.text('İşlemi sil'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Vazgeç'));
      await tester.pumpAndSettle();
      expect(transactions.items.length, 4);

      await tester.tap(find.text('İşlemi sil'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Sil'));
      await tester.pumpAndSettle();

      expect(transactions.items.length, 3);
      expect(find.text('-15.000,00 ₺'), findsNothing);
      expect(_text(tester, 'sum-expense'), '300,00 ₺');
    });
  });

  test('tarih yardımcıları', () {
    expect(Dates.toDb(DateTime(2026, 1, 5)), '2026-01-05');
    expect(Dates.fromDb('2026-01-05'), DateTime(2026, 1, 5));
    expect(Dates.addMonths(DateTime(2026, 12), 1), DateTime(2027, 1));
    expect(Dates.addMonths(DateTime(2026, 1), -1), DateTime(2025, 12));
  });
}
