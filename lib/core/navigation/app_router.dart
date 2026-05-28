import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../ui/screens/dashboard/dashboard_screen.dart';
import '../../ui/screens/pos/pos_screen.dart';
import '../../ui/navigation/main_scaffold.dart';

/// Application router configuration using GoRouter.
/// This replaces the mixed named-routes / push approach.
/// M-13: Navigation unification — incremental migration.
///
/// NOTE: ShellRoute requires MainScaffold to accept a `child` parameter.
/// Since MainScaffold currently manages its own IndexedStack internally,
/// we use a simpler approach for now. Full ShellRoute integration will
/// be done when MainScaffold is refactored to accept a child widget.
class AppRouter {
  AppRouter._();

  static final GoRouter router = GoRouter(
    initialLocation: '/',
    routes: [
      GoRoute(
        path: '/',
        name: 'home',
        builder: (context, state) => const MainScaffold(),
      ),
      GoRoute(
        path: '/pos',
        name: 'pos',
        builder: (context, state) => const PosScreen(),
      ),
      GoRoute(
        path: '/dashboard',
        name: 'dashboard',
        builder: (context, state) => const DashboardScreen(),
      ),
      // Additional routes will be migrated incrementally
      // from the existing named routes in AppRouter.routes
    ],
  );
}
