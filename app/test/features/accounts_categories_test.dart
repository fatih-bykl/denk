import 'package:denk/app/app.dart';
import 'package:denk/app/routes.dart';
import 'package:denk/core/errors/data_failure.dart';
import 'package:denk/features/accounts/data/accounts_repository.dart';
import 'package:denk/features/categories/data/categories_repository.dart';
import 'package:denk/features/categories/domain/category.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import '../helpers/fake_backup.dart';
import '../helpers/fake_data_repositories.dart';

Future<void> _open(
  WidgetTester tester,
  String location, {
  FakeAccountsRepository? accounts,
  FakeCategoriesRepository? categories,
}) async {
  tester.view.physicalSize = const Size(400, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        ...backupTestOverrides(),
        accountsRepositoryProvider.overrideWithValue(
          accounts ?? FakeAccountsRepository(),
        ),
        categoriesRepositoryProvider.overrideWithValue(
          categories ?? FakeCategoriesRepository(),
        ),
      ],
      child: const DenkApp(),
    ),
  );
  await tester.pumpAndSettle();
  final context = tester.element(find.byType(Scaffold).first);
  GoRouter.of(context).go(location);
  await tester.pumpAndSettle();
}

Finder _field(String label) => find.widgetWithText(TextFormField, label);

void main() {
  group('Hesaplar', () {
    testWidgets('Ayarlar menüsünden açılır', (tester) async {
      await _open(tester, Routes.settings);
      await tester.tap(find.text('Hesaplar'));
      await tester.pumpAndSettle();
      expect(find.text('Toplam bakiye'), findsOneWidget);
    });

    testWidgets('bakiyeler ve toplam yalnızca aktif hesaplardan', (
      tester,
    ) async {
      final repo = FakeAccountsRepository()
        ..add('Nakit', opening: 100000, movement: 25050)
        ..add('Kredi kartı', opening: -50000)
        ..add('Eski hesap', opening: 999900, archived: true);
      await _open(tester, Routes.accounts, accounts: repo);

      expect(find.text('1.250,50 ₺'), findsOneWidget);
      expect(find.text('-500,00 ₺'), findsOneWidget);
      expect(
        tester.widget<Text>(find.byKey(const Key('total-balance'))).data,
        '750,50 ₺',
      );
      expect(find.text('Arşivlenen hesaplar (1)'), findsOneWidget);
      expect(find.text('Eski hesap'), findsNothing);
    });

    testWidgets('yeni hesap eklenir ve toplam güncellenir', (tester) async {
      final repo = FakeAccountsRepository()..add('Nakit', opening: 10000);
      await _open(tester, Routes.accounts, accounts: repo);

      await tester.tap(find.text('Hesap ekle'));
      await tester.pumpAndSettle();
      await tester.enterText(_field('Hesap adı'), 'Banka');
      await tester.enterText(_field('Açılış bakiyesi'), '1.250,5');
      await tester.tap(find.text('Kaydet'));
      await tester.pumpAndSettle();

      expect(repo.byName('Banka').openingBalance, 125050);
      expect(find.text('Banka'), findsOneWidget);
      expect(
        tester.widget<Text>(find.byKey(const Key('total-balance'))).data,
        '1.350,50 ₺',
      );
    });

    testWidgets('geçersiz tutar kaydedilmez', (tester) async {
      final repo = FakeAccountsRepository()..add('Nakit');
      await _open(tester, Routes.accounts, accounts: repo);

      await tester.tap(find.text('Hesap ekle'));
      await tester.pumpAndSettle();
      await tester.enterText(_field('Hesap adı'), 'Banka');
      await tester.enterText(_field('Açılış bakiyesi'), '12,345');
      await tester.tap(find.text('Kaydet'));
      await tester.pumpAndSettle();

      expect(
        find.text('Geçerli bir tutar gir (ör. 1.250,50).'),
        findsOneWidget,
      );
      expect(() => repo.byName('Banka'), throwsStateError);
    });

    testWidgets('düzenlenen açılış bakiyesi bakiyeye yansır', (tester) async {
      final repo = FakeAccountsRepository()
        ..add('Nakit', opening: 10000, movement: -2500);
      await _open(tester, Routes.accounts, accounts: repo);
      expect(find.text('75,00 ₺').evaluate(), isNotEmpty);

      await tester.tap(find.widgetWithText(ListTile, 'Nakit'));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<EditableText>(
              find.descendant(
                of: _field('Açılış bakiyesi'),
                matching: find.byType(EditableText),
              ),
            )
            .controller
            .text,
        '100,00',
      );
      await tester.enterText(_field('Açılış bakiyesi'), '200');
      await tester.tap(find.text('Kaydet'));
      await tester.pumpAndSettle();

      expect(repo.byName('Nakit').balance, 17500);
      expect(find.text('175,00 ₺').evaluate(), isNotEmpty);
    });

    testWidgets('son aktif hesap arşivlenemez, diğerleri arşivlenir', (
      tester,
    ) async {
      final repo = FakeAccountsRepository()..add('Nakit');
      await _open(tester, Routes.accounts, accounts: repo);

      await tester.tap(find.widgetWithText(ListTile, 'Nakit'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Arşivle'));
      await tester.pumpAndSettle();
      expect(find.text('En az bir aktif hesap olmalı.'), findsOneWidget);
      expect(repo.byName('Nakit').isArchived, isFalse);
    });

    testWidgets('sunucu hatası formda gösterilir', (tester) async {
      final repo = FakeAccountsRepository()..add('Nakit');
      await _open(tester, Routes.accounts, accounts: repo);

      repo.nextFailure = const DataFailure('Bu adla bir kayıt zaten var.');
      await tester.tap(find.text('Hesap ekle'));
      await tester.pumpAndSettle();
      await tester.enterText(_field('Hesap adı'), 'Nakit');
      await tester.tap(find.text('Kaydet'));
      await tester.pumpAndSettle();

      expect(find.text('Bu adla bir kayıt zaten var.'), findsOneWidget);
      expect(find.text('Yeni hesap'), findsOneWidget);
    });
  });

  group('Kategoriler', () {
    FakeCategoriesRepository seed() => FakeCategoriesRepository()
      ..add(EntryKind.expense, 'Market', icon: 'shopping_cart')
      ..add(EntryKind.expense, 'Eski gider', archived: true)
      ..add(EntryKind.income, 'Maaş', icon: 'payments');

    testWidgets('gider ve gelir sekmeleri ayrı listelenir', (tester) async {
      await _open(tester, Routes.categories, categories: seed());

      expect(find.text('Market'), findsOneWidget);
      expect(find.text('Maaş'), findsNothing);
      expect(find.text('Arşivlenen kategoriler (1)'), findsOneWidget);

      await tester.tap(find.text('Gelir'));
      await tester.pumpAndSettle();
      expect(find.text('Maaş'), findsOneWidget);
      expect(find.text('Market'), findsNothing);
    });

    testWidgets('gelir sekmesinden eklenen kategori gelir türünde olur', (
      tester,
    ) async {
      final repo = seed();
      await _open(tester, Routes.categories, categories: repo);

      await tester.tap(find.text('Gelir'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Kategori ekle'));
      await tester.pumpAndSettle();
      expect(find.text('Yeni gelir kategorisi'), findsOneWidget);
      await tester.enterText(_field('Kategori adı'), 'Prim');
      await tester.tap(find.byKey(const Key('icon-savings')));
      await tester.tap(find.text('Kaydet'));
      await tester.pumpAndSettle();

      final created = repo.byName('Prim');
      expect(created.kind, EntryKind.income);
      expect(created.icon, 'savings');
      expect(find.text('Prim'), findsOneWidget);
    });

    testWidgets('aynı adlı kategori hatası gösterilir', (tester) async {
      await _open(tester, Routes.categories, categories: seed());

      await tester.tap(find.text('Kategori ekle'));
      await tester.pumpAndSettle();
      await tester.enterText(_field('Kategori adı'), 'Market');
      await tester.tap(find.text('Kaydet'));
      await tester.pumpAndSettle();

      expect(find.text('Bu adla bir kayıt zaten var.'), findsOneWidget);
    });

    testWidgets('kategori arşivlenir', (tester) async {
      final repo = seed();
      await _open(tester, Routes.categories, categories: repo);

      await tester.tap(find.widgetWithText(ListTile, 'Market'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Arşivle'));
      await tester.pumpAndSettle();

      expect(repo.byName('Market').isArchived, isTrue);
      expect(find.text('Arşivlenen kategoriler (2)'), findsOneWidget);
    });
  });
}
