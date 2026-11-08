import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/backup/backup_controller.dart';
import 'router.dart';
import 'theme/app_theme.dart';

class DenkApp extends ConsumerStatefulWidget {
  const DenkApp({super.key});

  @override
  ConsumerState<DenkApp> createState() => _DenkAppState();
}

class _DenkAppState extends ConsumerState<DenkApp> {
  late final AppLifecycleListener _lifecycle;

  @override
  void initState() {
    super.initState();
    // Drive yedeği bağlıysa: açılışta bağlantıyı tazele ve gerekirse yedekle;
    // uygulama arka plana geçerken değişiklik varsa yedekle.
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => ref.read(backupControllerProvider.notifier).onAppStart(),
    );
    _lifecycle = AppLifecycleListener(
      onHide: () =>
          ref.read(backupControllerProvider.notifier).backupIfChanged(),
    );
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'Denk',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      locale: const Locale('tr', 'TR'),
      supportedLocales: const [Locale('tr', 'TR')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      routerConfig: ref.watch(routerProvider),
    );
  }
}
