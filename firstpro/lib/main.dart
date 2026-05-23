import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'core/constants/app_constants.dart';
import 'core/theme/app_theme.dart';
import 'data/datasources/database_helper.dart';
import 'ui/navigation/app_router.dart';
import 'ui/navigation/main_scaffold.dart';
import 'ui/screens/app_lock/app_lock_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();

  // Set preferred orientations for a typical accounting app (portrait-first).
  // SystemChrome.setPreferredOrientations can be added here if needed.

  runApp(const FirstProApp());
}

/// Root widget for the FirstPro accounting application.
///
/// Checks if PIN lock is enabled at startup:
/// - If PIN is enabled ('pin_enabled' = '1'), shows [AppLockScreen] first.
/// - If PIN is not enabled, goes directly to [MainScaffold].
class FirstProApp extends StatefulWidget {
  const FirstProApp({super.key});

  @override
  State<FirstProApp> createState() => _FirstProAppState();
}

class _FirstProAppState extends State<FirstProApp> {
  /// null = still loading, true = PIN enabled, false = PIN disabled
  bool? _pinEnabled;

  @override
  void initState() {
    super.initState();
    _checkPinEnabled();
  }

  Future<void> _checkPinEnabled() async {
    final db = DatabaseHelper();
    final pinEnabled = await db.getSetting('pin_enabled');

    if (mounted) {
      setState(() {
        _pinEnabled = pinEnabled == '1';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      // ── Identity ────────────────────────────────────────────
      title: AppConstants.appName,
      debugShowCheckedModeBanner: false,

      // ── RTL / Arabic locale setup ───────────────────────────
      locale: const Locale(AppConstants.defaultLanguage),
      supportedLocales: const [
        Locale(AppConstants.localeAr),
        Locale(AppConstants.localeEn),
      ],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],

      // ── Force RTL direction ─────────────────────────────────
      builder: (context, child) {
        return Directionality(
          textDirection: TextDirection.rtl,
          child: child!,
        );
      },

      // ── Theming ─────────────────────────────────────────────
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: ThemeMode.system,

      // ── Navigation ──────────────────────────────────────────
      // Show AppLockScreen if PIN is enabled, otherwise MainScaffold.
      // While loading, show a splash/loading indicator.
      home: _buildHome(),
      routes: AppRouter.routes,
    );
  }

  Widget _buildHome() {
    // Still checking the pin_enabled setting
    if (_pinEnabled == null) {
      return Directionality(
        textDirection: TextDirection.rtl,
        child: Scaffold(
          backgroundColor: Colors.white,
          body: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.calculate_outlined,
                  size: 64,
                  color: AppConstants.appName.isNotEmpty
                      ? const Color(0xFF1A73E8)
                      : Colors.blue,
                ),
                const SizedBox(height: 24),
                const SizedBox(
                  width: 32,
                  height: 32,
                  child: CircularProgressIndicator(strokeWidth: 3),
                ),
              ],
            ),
          ),
        ),
      );
    }

    // PIN lock enabled → show lock screen first
    if (_pinEnabled == true) {
      return const AppLockScreen();
    }

    // PIN not enabled → go directly to main app
    return const MainScaffold();
  }
}
