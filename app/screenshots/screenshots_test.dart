// Tanıtım sayfası ve mağaza için uygulama ekran görüntüleri.
//
// Örnek verilerle (gerçek kullanıcı verisi değil) uygulamayı koyu temada açar ve
// her ekranı PNG olarak kaydeder:
//
//   cd app && flutter test --update-goldens screenshots/screenshots_test.dart
//
// Çıktı: app/screenshots/out/*.png (1080×2400, 20:9 telefon ekranı).

import 'dart:io';

import 'package:denk/app/app.dart';
import 'package:denk/app/routes.dart';
import 'package:denk/core/database/app_database.dart';
import 'package:denk/core/date/dates.dart';
import 'package:denk/core/recurrence/recurrence.dart';
import 'package:denk/features/accounts/data/accounts_repository.dart';
import 'package:denk/features/categories/data/categories_repository.dart';
import 'package:denk/features/categories/domain/category.dart';
import 'package:denk/features/debts/application/debt_service.dart';
import 'package:denk/features/debts/data/debts_repository.dart';
import 'package:denk/features/debts/domain/debt.dart';
import 'package:denk/features/schedule/application/schedule_providers.dart';
import 'package:denk/features/schedule/data/schedule_repository.dart';
import 'package:denk/features/schedule/domain/occurrence.dart';
import 'package:denk/features/schedule/domain/payment_schedule.dart';
import 'package:denk/features/transactions/data/transactions_repository.dart';
import 'package:denk/features/transactions/domain/transaction.dart';
import 'package:denk/services/backup/backup_controller.dart';
import 'package:denk/services/backup/backup_store.dart';
import 'package:denk/services/notifications/notification_service.dart';
import 'package:denk/services/notifications/reminder_sync.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';

import '../test/helpers/fake_backup.dart';
import '../test/helpers/test_app.dart' show FakeNotificationService;

final today = DateTime(2026, 11, 15);
final now = DateTime(2026, 11, 15, 10, 30);

/// Flutter SDK'daki Roboto ve Material simge yazı tiplerini yükler
/// (testlerde varsayılan yazı tipi kutulardan oluşur).
Future<void> _loadFonts() async {
  // flutter_tester: <flutter>/bin/cache/artifacts/engine/<platform>/flutter_tester
  final cache = File(Platform.resolvedExecutable).parent.parent.parent.parent;
  final fonts = Directory('${cache.path}/artifacts/material_fonts');
  Future<ByteData> read(String name) async =>
      ByteData.sublistView(File('${fonts.path}/$name').readAsBytesSync());

  final roboto = FontLoader('Roboto');
  for (final w in ['Light', 'Regular', 'Medium', 'Bold', 'Black']) {
    roboto.addFont(read('Roboto-$w.ttf'));
  }
  await roboto.load();
  final icons = FontLoader('MaterialIcons')
    ..addFont(read('MaterialIcons-Regular.otf'));
  await icons.load();
}

/// Örnek veriler: üç hesap, iki aylık gelir/gider, düzenli ödemeler, borç/alacak.
Future<AppDatabase> _demoDatabase() async {
  final db = AppDatabase.inMemory();
  final accounts = LocalAccountsRepository(db);
  final categories = LocalCategoriesRepository(db);
  final transactions = LocalTransactionsRepository(db);
  final schedules = LocalScheduleRepository(db);
  final debts = LocalDebtsRepository(db);

  final cash = (await accounts.fetchAll()).single.id;
  await accounts.update(cash, name: 'Nakit', openingBalance: 350000);
  await accounts.create(name: 'Maaş hesabı', openingBalance: 4250000);
  await accounts.create(name: 'Kredi kartı', openingBalance: -875000);
  final all = await accounts.fetchAll();
  final bank = all.firstWhere((a) => a.name == 'Maaş hesabı').id;
  final card = all.firstWhere((a) => a.name == 'Kredi kartı').id;

  final cats = {for (final c in await categories.fetchAll()) c.name: c};
  String cat(String name, EntryKind kind) =>
      cats.values.firstWhere((c) => c.name == name && c.kind == kind).id;

  Future<void> tx(
    String account,
    EntryKind type,
    int lira,
    DateTime day,
    String category, [
    String? note,
  ]) => transactions.create(
    TransactionDraft(
      accountId: account,
      type: type,
      amount: lira * 100,
      occurredOn: day,
      categoryId: cat(category, type),
      note: note,
    ),
  );

  const inc = EntryKind.income;
  const exp = EntryKind.expense;
  for (final m in [9, 10, 11]) {
    DateTime d(int day) => DateTime(2026, m, day);
    await tx(bank, inc, 62000, d(1), 'Maaş');
    await tx(bank, exp, 2850, d(3), 'Market', 'Haftalık alışveriş');
    await tx(card, exp, 1240, d(6), 'Yeme-İçme', 'Akşam yemeği');
    await tx(cash, exp, 450, d(8), 'Ulaşım', 'İstanbulkart');
    await tx(card, exp, 3150, d(10), 'Market');
    await tx(bank, exp, 1180, d(12), 'Faturalar', 'Doğalgaz');
    await tx(card, exp, 2400, d(14), 'Giyim', 'Mont');
    if (m < 11) {
      await tx(bank, exp, 18000, d(5), 'Kira');
      await tx(bank, inc, 8500, d(20), 'Ek gelir', 'Serbest iş');
      await tx(card, exp, 2650, d(22), 'Market');
      await tx(card, exp, 990, d(25), 'Eğlence', 'Konser');
      await tx(cash, exp, 600, d(27), 'Sağlık', 'Eczane');
    }
  }
  await tx(cash, exp, 185, today, 'Yeme-İçme', 'Kahve');

  // Düzenli ödemeler.
  Future<String> plan(
    String title,
    int lira,
    DateTime start, {
    String? category,
    int remind = 3,
    CashFlow flow = CashFlow.outflow,
  }) async {
    final draft = ScheduleDraft(
      title: title,
      flow: flow,
      amount: lira * 100,
      frequency: Frequency.monthly,
      startDate: start,
      remindDaysBefore: remind,
      categoryId: category,
    );
    final id = await schedules.createSchedule(draft);
    await syncSchedule(schedules, PaymentSchedule.fromDraft(id, draft), today);
    return id;
  }

  final rent = await plan(
    'Kira',
    18000,
    DateTime(2026, 1, 5),
    category: cat('Kira', exp),
  );
  await plan(
    'Elektrik',
    1250,
    DateTime(2026, 1, 18),
    category: cat('Faturalar', exp),
    remind: 5,
  );
  await plan(
    'İnternet',
    650,
    DateTime(2026, 1, 24),
    category: cat('Faturalar', exp),
  );
  await plan(
    'Spor salonu',
    900,
    DateTime(2026, 1, 28),
    category: cat('Abonelikler', exp),
  );
  await plan(
    'Kira geliri (dükkân)',
    9500,
    DateTime(2026, 1, 10),
    category: cat('Kira geliri', inc),
    flow: CashFlow.inflow,
  );

  Future<Occurrence> occ(String scheduleId, DateTime due) async =>
      (await schedules.fetchOccurrences()).firstWhere(
        (o) => o.scheduleId == scheduleId && o.dueDate == due,
      );
  await schedules.pay(
    (await occ(rent, DateTime(2026, 11, 5))).id,
    accountId: bank,
    amount: 1800000,
    paidOn: DateTime(2026, 11, 5),
  );
  final incomePlan = (await schedules.fetchSchedules())
      .firstWhere((s) => s.flow == CashFlow.inflow)
      .id;
  await schedules.pay(
    (await occ(incomePlan, DateTime(2026, 11, 10))).id,
    accountId: bank,
    amount: 950000,
    paidOn: DateTime(2026, 11, 10),
  );

  // Borç ve alacaklar.
  final service = DebtService(debts: debts, schedules: schedules, today: today);
  await service.save(
    draft: const DebtDraft(
      direction: DebtDirection.payable,
      counterparty: 'Teknoloji Mağazası',
      title: 'Telefon',
      totalAmount: 3600000,
      installmentCount: 12,
    ),
    firstInstallment: DateTime(2026, 8, 15),
  );
  final phoneDebt = (await debts.fetchAll()).single.id;
  for (final m in [8, 9, 10]) {
    await transactions.create(
      TransactionDraft(
        accountId: card,
        type: exp,
        amount: 300000,
        occurredOn: DateTime(2026, m, 15),
        categoryId: cat('Kredi ve borç ödemesi', exp),
        note: 'Telefon taksiti',
        debtId: phoneDebt,
      ),
    );
  }
  await service.save(
    draft: DebtDraft(
      direction: DebtDirection.receivable,
      counterparty: 'Ayşe',
      title: 'Borç verdim',
      totalAmount: 500000,
      dueDate: DateTime(2026, 12, 31),
    ),
  );
  final ayse = (await debts.fetchAll()).firstWhere(
    (d) => d.counterparty == 'Ayşe',
  );
  await transactions.create(
    TransactionDraft(
      accountId: cash,
      type: inc,
      amount: 200000,
      occurredOn: DateTime(2026, 11, 2),
      categoryId: cat('Alacak tahsilatı', inc),
      debtId: ayse.id,
    ),
  );
  await service.save(
    draft: DebtDraft(
      direction: DebtDirection.payable,
      counterparty: 'Mehmet',
      title: 'Tatil masrafı',
      totalAmount: 450000,
      dueDate: DateTime(2026, 12, 10),
    ),
  );

  // Drive yedeği bağlı görünsün.
  db
    ..setSetting(BackupSettings.enabled, '1')
    ..setSetting(BackupSettings.account, 'ornek@gmail.com')
    ..setSetting(BackupSettings.auto, '1')
    ..setSetting(BackupSettings.dirty, '0')
    ..setSetting(
      BackupSettings.lastBackupAt,
      DateTime(2026, 11, 15, 9, 42).toUtc().toIso8601String(),
    );
  return db;
}

void main() {
  late AppDatabase db;
  late FakeDriveConnection drive;

  setUpAll(() async {
    await initializeDateFormatting('tr_TR');
    Intl.defaultLocale = 'tr_TR';
    await _loadFonts();
  });

  setUp(() async {
    db = await _demoDatabase();
    drive = FakeDriveConnection()..signedIn = true;
    for (final (i, at) in [
      DateTime(2026, 11, 15, 9, 42),
      DateTime(2026, 11, 14, 21, 10),
      DateTime(2026, 11, 13, 19, 5),
      DateTime(2026, 11, 12, 22, 30),
    ].indexed) {
      drive.store.files['f$i'] = (
        BackupFile(
          id: 'f$i',
          name: 'yedek.db',
          createdAt: at,
          sizeBytes: 49152,
        ),
        Uint8List(0),
      );
    }
  });

  tearDown(() => db.close());

  Future<void> shoot(
    WidgetTester tester,
    String name,
    String location, {
    Future<void> Function()? then,
  }) async {
    debugDisableShadows = false;
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.75;
    tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
    addTearDown(tester.view.reset);
    addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);

    await tester.pumpWidget(
      ProviderScope(
        retry: (_, _) => null,
        overrides: [
          ...backupTestOverrides(database: db, connection: drive),
          todayProvider.overrideWithValue(today),
          nowProvider.overrideWithValue(now),
          notificationServiceProvider.overrideWithValue(
            FakeNotificationService(),
          ),
        ],
        child: const RepaintBoundary(child: DenkApp()),
      ),
    );
    await tester.pumpAndSettle();
    if (location != Routes.dashboard) {
      GoRouter.of(tester.element(find.byType(Scaffold).first)).go(location);
      await tester.pumpAndSettle();
    }
    if (then != null) {
      await then();
      await tester.pumpAndSettle();
    }
    await expectLater(
      find.byType(RepaintBoundary).first,
      matchesGoldenFile('out/$name.png'),
    );
    debugDisableShadows = true;
  }

  testWidgets('özet', (t) => shoot(t, 'ozet', Routes.dashboard));
  // Bir bölümü ekranın üstüne kaydırır (başlığı biraz aşağıda kalsın diye geri çeker).
  Future<void> Function() scrollTo(
    WidgetTester t,
    String text, [
    double back = 40,
  ]) => () async {
    // Liste, ekran dışındaki kartları henüz oluşturmamış olabilir: önce oraya kaydır.
    await t.scrollUntilVisible(
      find.text(text),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await t.ensureVisible(find.text(text));
    await t.pumpAndSettle();
    await t.drag(find.byType(Scrollable).first, Offset(0, back));
  };
  testWidgets(
    'özet halka',
    (t) => shoot(
      t,
      'ozet-halka',
      Routes.dashboard,
      then: scrollTo(t, 'Kasım 2026', 70),
    ),
  );
  testWidgets(
    'özet kategoriler',
    (t) => shoot(
      t,
      'ozet-kategori',
      Routes.dashboard,
      then: scrollTo(t, 'Gider kategorileri', 60),
    ),
  );
  testWidgets(
    'özet grafik',
    (t) => shoot(
      t,
      'ozet-grafik',
      Routes.dashboard,
      then: scrollTo(t, 'Nakit akışı · son 6 ay', 40),
    ),
  );
  testWidgets('işlemler', (t) => shoot(t, 'islemler', Routes.transactions));
  testWidgets('takvim', (t) => shoot(t, 'takvim', Routes.schedule));
  testWidgets('borçlar', (t) => shoot(t, 'borclar', Routes.debts));
  testWidgets('hesaplar', (t) => shoot(t, 'hesaplar', Routes.accounts));
  testWidgets('yedek', (t) => shoot(t, 'yedek', Routes.backup));
  testWidgets(
    'işlem ekle',
    (t) => shoot(
      t,
      'islem-ekle',
      Routes.transactions,
      then: () => t.tap(find.text('İşlem ekle')),
    ),
  );
}
