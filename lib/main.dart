import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'l10n/generated/app_localizations.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'core/constants/app_constants.dart';
import 'core/di/service_locator.dart';
import 'core/theme/app_theme.dart';
import 'data/datasources/database_helper.dart';
import 'ui/navigation/app_router.dart';
import 'ui/navigation/main_scaffold.dart';
import 'ui/screens/app_lock/app_lock_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await setupLocator();

  // TODO: Implement user authentication/login system before app launch.
  // Currently the app has no login screen — any user with the device can access all data.
  // A proper login flow should:
  // 1. Show a login screen on first launch to create an admin account.
  // 2. Require username/password (or biometric) on subsequent launches.
  // 3. Support multiple user roles (admin, cashier, etc.) with different permissions.
  // 4. Store credentials securely (hash + salt) in the database or flutter_secure_storage.

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

  /// Theme mode loaded from settings: 0=light, 1=dark, 2=system
  int _themeModeIndex = 2; // Default to system

  static const FlutterSecureStorage _secureStorage = FlutterSecureStorage();

  @override
  void initState() {
    super.initState();
    _initApp();
  }

  Future<void> _initApp() async {
    final db = DatabaseHelper();

    // Load PIN enabled state from secure storage with DB fallback for migration
    String? pinEnabled;
    try {
      pinEnabled = await _secureStorage.read(key: 'pin_enabled');
    } catch (_) {
      // Secure storage read failed — try DB fallback
    }
    if (pinEnabled == null) {
      pinEnabled = await db.getSetting('pin_enabled');
      if (pinEnabled != null && pinEnabled.isNotEmpty) {
        // Migrate to secure storage
        try {
          await _secureStorage.write(key: 'pin_enabled', value: pinEnabled);
        } catch (_) {}
        await db.deleteSetting('pin_enabled');
      }
    }

    // Load saved theme mode
    final themeModeStr = await db.getSetting('theme_mode_index');

    if (mounted) {
      setState(() {
        _pinEnabled = pinEnabled == '1';
        if (themeModeStr != null) {
          _themeModeIndex = int.tryParse(themeModeStr) ?? 2;
        }
      });
    }
  }

  ThemeMode _getThemeMode() {
    switch (_themeModeIndex) {
      case 0:
        return ThemeMode.light;
      case 1:
        return ThemeMode.dark;
      default:
        return ThemeMode.system;
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      // ── Identity ────────────────────────────────────────────
      title: AppConstants.appName,
      debugShowCheckedModeBanner: false,

      // ── RTL / Arabic locale setup ───────────────────────────
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      locale: const Locale('ar'),
      supportedLocales: AppLocalizations.supportedLocales,

      // ── Theming ─────────────────────────────────────────────
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: _getThemeMode(),

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
      return Scaffold(
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
