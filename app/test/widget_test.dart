import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers/test_app.dart';

void main() {
  setUpAll(initTestLocale);

  testWidgets('uygulama giriş istemeden özet ekranıyla açılır', (tester) async {
    await pumpTestApp(tester, size: const Size(400, 800));

    expect(find.text('Toplam bakiye'), findsOneWidget);
    expect(find.byType(NavigationBar), findsOneWidget);
  });

  testWidgets('alt çubukla sekmeler arasında geçilir', (tester) async {
    await pumpTestApp(tester, size: const Size(400, 800));

    final labels = {
      'İşlemler': 'İşlem ekle',
      'Takvim': 'Plan ekle',
      'Borçlar': 'Kayıt ekle',
      'Ayarlar': 'Tüm verilerimi sil',
    };
    for (final MapEntry(key: label, value: content) in labels.entries) {
      await tester.tap(
        find.descendant(
          of: find.byType(NavigationBar),
          matching: find.text(label),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text(content), findsOneWidget);
    }
  });

  testWidgets('geniş ekranda yan menü gösterilir', (tester) async {
    await pumpTestApp(tester, size: const Size(1200, 800));

    expect(find.byType(NavigationRail), findsOneWidget);
    expect(find.byType(NavigationBar), findsNothing);
  });
}
