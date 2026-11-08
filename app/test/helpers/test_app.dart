import 'package:denk/app/app.dart';
import 'package:denk/core/date/dates.dart';
import 'package:denk/core/errors/data_failure.dart';
import 'package:denk/features/accounts/data/accounts_repository.dart';
import 'package:denk/features/categories/data/categories_repository.dart';
import 'package:denk/features/debts/data/debts_repository.dart';
import 'package:denk/features/schedule/data/schedule_repository.dart';
import 'package:denk/features/settings/data/data_reset_repository.dart';
import 'package:denk/features/transactions/data/transactions_repository.dart';
import 'package:denk/services/notifications/notification_service.dart';
import 'package:denk/services/notifications/reminder.dart';
import 'package:denk/services/notifications/reminder_sync.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'fake_backup.dart';
import 'fake_data_repositories.dart';

/// Testlerde sabit "bugün": 5 Kasım 2026, Perşembe.
final testToday = DateTime(2026, 11, 5);

/// Testlerde sabit "şimdi": bugün saat 14:00.
final testNow = DateTime(2026, 11, 5, 14);

/// Türkçe tarih biçimleri için bir kez çağrılır.
Future<void> initTestLocale() => initializeDateFormatting('tr_TR');

/// Sahte depolarla uygulamayı kurar; [location] verilirse oraya gider.
Future<void> pumpTestApp(
  WidgetTester tester, {
  FakeAccountsRepository? accounts,
  FakeCategoriesRepository? categories,
  FakeTransactionsRepository? transactions,
  FakeScheduleRepository? schedule,
  FakeDebtsRepository? debts,
  FakeNotificationService? notifications,
  FakeDataResetRepository? dataReset,
  FakeDriveConnection? drive,
  String? location,
  Size size = const Size(400, 900),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final accountsRepo = accounts ?? FakeAccountsRepository();
  final transactionsRepo =
      transactions ?? FakeTransactionsRepository(accountsRepo);
  final scheduleRepo = schedule ?? FakeScheduleRepository(transactionsRepo);
  await tester.pumpWidget(
    ProviderScope(
      // Testlerde hata sonrası otomatik yeniden deneme kapalı (bekleyen zamanlayıcı kalmasın).
      retry: (_, _) => null,
      overrides: [
        ...backupTestOverrides(connection: drive),
        todayProvider.overrideWithValue(testToday),
        nowProvider.overrideWithValue(testNow),
        notificationServiceProvider.overrideWithValue(
          notifications ?? FakeNotificationService(),
        ),
        dataResetRepositoryProvider.overrideWithValue(
          dataReset ?? FakeDataResetRepository(),
        ),
        accountsRepositoryProvider.overrideWithValue(accountsRepo),
        categoriesRepositoryProvider.overrideWithValue(
          categories ?? FakeCategoriesRepository(),
        ),
        transactionsRepositoryProvider.overrideWithValue(transactionsRepo),
        scheduleRepositoryProvider.overrideWithValue(scheduleRepo),
        debtsRepositoryProvider.overrideWithValue(
          debts ?? FakeDebtsRepository(transactionsRepo, scheduleRepo),
        ),
      ],
      child: const DenkApp(),
    ),
  );
  await tester.pumpAndSettle();
  if (location != null) {
    GoRouter.of(tester.element(find.byType(Scaffold).first)).go(location);
    await tester.pumpAndSettle();
  }
}

Finder formField(String label) => find.widgetWithText(TextFormField, label);

/// Kurulan bildirimleri bellekte tutan sahte bildirim servisi.
class FakeNotificationService implements NotificationService {
  FakeNotificationService({this.enabled = true});

  bool enabled;
  int permissionRequests = 0;
  List<Reminder> scheduled = const [];
  int replaceCalls = 0;

  @override
  bool get isSupported => true;

  @override
  Future<bool> areEnabled() async => enabled;

  @override
  Future<bool> requestPermission() async {
    permissionRequests++;
    enabled = true;
    return true;
  }

  @override
  Future<void> replaceAll(List<Reminder> reminders) async {
    replaceCalls++;
    scheduled = List.of(reminders);
  }

  int testRequests = 0;

  @override
  Future<DateTime> scheduleTest(Duration delay) async {
    testRequests++;
    return testNow.add(delay);
  }
}

/// "Tüm verilerimi sil" çağrılarını sayan sahte depo.
class FakeDataResetRepository implements DataResetRepository {
  int calls = 0;
  DataFailure? failure;

  @override
  Future<void> deleteAllData() async {
    if (failure != null) throw failure!;
    calls++;
  }
}
