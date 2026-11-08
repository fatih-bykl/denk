import 'package:denk/app/routes.dart';
import 'package:denk/core/errors/data_failure.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/test_app.dart';

void main() {
  setUpAll(initTestLocale);

  late FakeDataResetRepository reset;
  late FakeNotificationService notifications;

  setUp(() {
    reset = FakeDataResetRepository();
    notifications = FakeNotificationService();
  });

  Future<void> openDialog(WidgetTester tester) async {
    await pumpTestApp(
      tester,
      dataReset: reset,
      notifications: notifications,
      location: Routes.settings,
      size: const Size(420, 1200),
    );
    await tester.tap(find.text('Tüm verilerimi sil'));
    await tester.pumpAndSettle();
  }

  FilledButton deleteButton(WidgetTester tester) => tester.widget<FilledButton>(
    find.widgetWithText(FilledButton, 'Tümünü sil'),
  );

  testWidgets('SİL yazılmadan silme düğmesi kapalı', (tester) async {
    await openDialog(tester);

    expect(find.text('Tüm verilerin silinsin mi?'), findsOneWidget);
    expect(deleteButton(tester).onPressed, isNull);
    await tester.enterText(find.byType(TextField), 'evet');
    await tester.pump();
    expect(deleteButton(tester).onPressed, isNull);
  });

  testWidgets('onaylanınca veriler silinir ve bildirimler temizlenir', (
    tester,
  ) async {
    await openDialog(tester);

    await tester.enterText(find.byType(TextField), 'SİL');
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, 'Tümünü sil'));
    await tester.pumpAndSettle();

    expect(reset.calls, 1);
    expect(notifications.scheduled, isEmpty);
    expect(notifications.replaceCalls, greaterThan(0));
    expect(find.text('Tüm verilerin silinsin mi?'), findsNothing);
    expect(find.text('Tüm verilerin silindi.'), findsOneWidget);
  });

  testWidgets('vazgeçilirse hiçbir şey silinmez', (tester) async {
    await openDialog(tester);

    await tester.tap(find.text('Vazgeç'));
    await tester.pumpAndSettle();

    expect(reset.calls, 0);
    expect(find.text('Tüm verilerin silinsin mi?'), findsNothing);
  });

  testWidgets('silinemezse hata gösterilir, pencere açık kalır', (
    tester,
  ) async {
    reset.failure = const DataFailure(
      'Kayıt kaydedilemedi. Lütfen tekrar dene.',
    );
    await openDialog(tester);

    await tester.enterText(find.byType(TextField), 'sil');
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, 'Tümünü sil'));
    await tester.pumpAndSettle();

    expect(reset.calls, 0);
    expect(find.text('Tüm verilerin silinsin mi?'), findsOneWidget);
    expect(
      find.text('Kayıt kaydedilemedi. Lütfen tekrar dene.'),
      findsOneWidget,
    );
  });
}
