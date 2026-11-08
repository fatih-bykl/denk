import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../services/notifications/reminder_sync.dart';

/// Dar ekranda alt çubuk, geniş ekranda yan menü gösterir.
class AppShell extends ConsumerWidget {
  const AppShell({super.key, required this.navigationShell});

  static const _wideBreakpoint = 720.0;

  static const _destinations = [
    (icon: Icons.dashboard_outlined, selected: Icons.dashboard, label: 'Özet'),
    (
      icon: Icons.receipt_long_outlined,
      selected: Icons.receipt_long,
      label: 'İşlemler',
    ),
    (
      icon: Icons.calendar_month_outlined,
      selected: Icons.calendar_month,
      label: 'Takvim',
    ),
    (
      icon: Icons.handshake_outlined,
      selected: Icons.handshake,
      label: 'Borçlar',
    ),
    (icon: Icons.settings_outlined, selected: Icons.settings, label: 'Ayarlar'),
  ];

  final StatefulNavigationShell navigationShell;

  void _select(int index) => navigationShell.goBranch(
    index,
    // Seçili sekmeye yeniden dokunmak sekmenin başına döndürür.
    initialLocation: index == navigationShell.currentIndex,
  );

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Oturum açıkken cihazdaki ödeme hatırlatmalarını güncel tutar
    // (planlar/dönemler değiştikçe yeniden çalışır; web'de hiçbir şey yapmaz).
    ref.watch(reminderSyncProvider);
    final isWide = MediaQuery.sizeOf(context).width >= _wideBreakpoint;

    if (!isWide) {
      return Scaffold(
        body: navigationShell,
        bottomNavigationBar: NavigationBar(
          selectedIndex: navigationShell.currentIndex,
          onDestinationSelected: _select,
          destinations: [
            for (final d in _destinations)
              NavigationDestination(
                icon: Icon(d.icon),
                selectedIcon: Icon(d.selected),
                label: d.label,
              ),
          ],
        ),
      );
    }

    return Scaffold(
      body: Row(
        children: [
          NavigationRail(
            selectedIndex: navigationShell.currentIndex,
            onDestinationSelected: _select,
            labelType: NavigationRailLabelType.all,
            destinations: [
              for (final d in _destinations)
                NavigationRailDestination(
                  icon: Icon(d.icon),
                  selectedIcon: Icon(d.selected),
                  label: Text(d.label),
                ),
            ],
          ),
          const VerticalDivider(width: 1),
          Expanded(child: navigationShell),
        ],
      ),
    );
  }
}
