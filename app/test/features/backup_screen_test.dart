import 'package:denk/app/routes.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/fake_backup.dart';
import '../helpers/test_app.dart';

Future<void> _connect(WidgetTester tester) async {
  await tester.tap(find.text('Google Drive’a bağlan'));
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(initTestLocale);

  testWidgets('Ayarlar yedeğin kapalı olduğunu gösterir', (tester) async {
    await pumpTestApp(tester, location: Routes.settings);
    expect(find.text('Google Drive yedeği'), findsOneWidget);
    expect(
      find.text('Kapalı · verilerin yalnızca bu telefonda'),
      findsOneWidget,
    );
  });

  testWidgets("bağlanınca hesap, son yedek ve yedek listesi görünür", (
    tester,
  ) async {
    final drive = FakeDriveConnection();
    await pumpTestApp(tester, drive: drive, location: Routes.backup);

    await _connect(tester);

    expect(find.text('ayse@gmail.com'), findsOneWidget);
    expect(find.textContaining('Son yedek:'), findsOneWidget);
    expect(find.textContaining('Otomatik yedekleme açık'), findsOneWidget);
    expect(find.text('Geri yükle'), findsOneWidget);
    expect(drive.store.uploads, 1);
  });

  testWidgets('geri yükleme önce onay ister', (tester) async {
    final drive = FakeDriveConnection();
    await pumpTestApp(tester, drive: drive, location: Routes.backup);
    await _connect(tester);

    await tester.tap(find.text('Geri yükle'));
    await tester.pumpAndSettle();
    expect(find.text('Bu yedek geri yüklensin mi?'), findsOneWidget);
    await tester.tap(find.text('Vazgeç'));
    await tester.pumpAndSettle();
    expect(find.text('Bu yedek geri yüklensin mi?'), findsNothing);
  });

  testWidgets('Google ayarı yoksa yedekleme kullanılamaz', (tester) async {
    await pumpTestApp(
      tester,
      drive: FakeDriveConnection(configured: false),
      location: Routes.backup,
    );
    expect(find.textContaining('henüz kullanılamıyor'), findsOneWidget);
    expect(find.text('Google Drive’a bağlan'), findsNothing);
  });
}
