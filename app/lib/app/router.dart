import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../features/accounts/presentation/accounts_screen.dart';
import '../features/categories/presentation/categories_screen.dart';
import '../features/dashboard/presentation/dashboard_screen.dart';
import '../features/debts/presentation/debts_screen.dart';
import '../features/schedule/presentation/schedule_screen.dart';
import '../features/schedule/presentation/schedules_screen.dart';
import '../features/settings/presentation/backup_screen.dart';
import '../features/settings/presentation/settings_screen.dart';
import '../features/transactions/presentation/transactions_screen.dart';
import 'routes.dart';
import 'shell/app_shell.dart';

final routerProvider = Provider<GoRouter>((ref) {
  final router = GoRouter(
    initialLocation: Routes.dashboard,
    routes: [
      StatefulShellRoute.indexedStack(
        builder: (context, state, shell) => AppShell(navigationShell: shell),
        branches: [
          _branch(Routes.dashboard, const DashboardScreen()),
          _branch(Routes.transactions, const TransactionsScreen()),
          _branch(
            Routes.schedule,
            const ScheduleScreen(),
            children: [
              GoRoute(
                path: Routes.schedulesSegment,
                builder: (context, state) => const SchedulesScreen(),
              ),
            ],
          ),
          _branch(Routes.debts, const DebtsScreen()),
          _branch(
            Routes.settings,
            const SettingsScreen(),
            children: [
              GoRoute(
                path: Routes.accountsSegment,
                builder: (context, state) => const AccountsScreen(),
              ),
              GoRoute(
                path: Routes.categoriesSegment,
                builder: (context, state) => const CategoriesScreen(),
              ),
              GoRoute(
                path: Routes.backupSegment,
                builder: (context, state) => const BackupScreen(),
              ),
            ],
          ),
        ],
      ),
    ],
  );
  ref.onDispose(router.dispose);
  return router;
});

StatefulShellBranch _branch(
  String path,
  Widget screen, {
  List<RouteBase> children = const [],
}) => StatefulShellBranch(
  routes: [
    GoRoute(path: path, builder: (context, state) => screen, routes: children),
  ],
);
