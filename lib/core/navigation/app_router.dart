import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../ui/screens/dashboard/dashboard_screen.dart';
import '../../ui/screens/pos/pos_screen.dart';
import '../../ui/navigation/main_scaffold.dart';

/// Application router configuration using GoRouter.
/// This replaces the mixed named-routes / push approach.
/// M-13: Navigation unification — incremental migration.
class AppRouter {
  AppRouter._();

  static final GoRouter router = GoRouter(
    initialLocation: '/',
    routes: [
      ShellRoute(
        builder: (context, state, child) => MainScaffold(child: child),
        routes: [
          GoRoute(
            path: '/',
            name: 'dashboard',
            builder: (context, state) => const DashboardScreen(),
          ),
          GoRoute(
            path: '/pos',
            name: 'pos',
            builder: (context, state) => const PosScreen(),
          ),
          // Additional routes will be migrated incrementally
          // from app_router.dart named routes
        ],
      ),
    ],
  );
}
