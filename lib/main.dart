import 'dart:async';
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
import 'ui/screens/splash/splash_screen.dart';

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

  runApp(const FirstProApp());
}

/// Root widget for the FirstPro accounting application.
///
/// Shows a modern animated splash screen for 3 seconds while initializing,
/// then transitions to either the PIN lock screen or the main scaffold.
class FirstProApp extends StatefulWidget {
  const FirstProApp({super.key});

  @override
  State<FirstProApp> createState() => _FirstProAppState();
}

class _FirstProAppState extends State<FirstProApp> {
  /// null = still on splash, true = PIN enabled, false = PIN disabled
  bool? _pinEnabled;

  /// Theme mode loaded from settings: 0=light, 1=dark, 2=system
  int _themeModeIndex = 2; // Default to system

  /// Whether initialization is complete (splash can transition)
  bool _initComplete = false;

  /// Whether splash timer has elapsed (3 seconds)
  bool _splashTimerDone = false;

  static const FlutterSecureStorage _secureStorage = FlutterSecureStorage();

  @override
  void initState() {
    super.initState();
    _startInit();
    _startSplashTimer();
  }

  /// Start the 3-second splash timer.
  void _startSplashTimer() {
    Future.delayed(const Duration(seconds: 3), () {
      if (mounted) {
        setState(() => _splashTimerDone = true);
      }
    });
  }

  /// Initialize app data in parallel with splash screen.
  Future<void> _startInit() async {
    bool? pinEnabled;
    int themeMode = 2;

    try {
      // Run init with a 5-second timeout to prevent getting stuck
      final result = await _loadAppSettings().timeout(
        const Duration(seconds: 5),
        onTimeout: () => (null, 2), // Fallback on timeout
      );
      pinEnabled = result.$1;
      themeMode = result.$2;
    } catch (e) {
      // If anything fails, use safe defaults and continue
      if (kDebugMode) {
        debugPrint('FirstProApp._startInit: $e');
      }
    }

    if (mounted) {
      setState(() {
        _pinEnabled = pinEnabled;
        _themeModeIndex = themeMode;
        _initComplete = true;
      });
    }
  }

  /// Load PIN state and theme from secure storage and database.
  /// Returns (pinEnabled, themeModeIndex).
  Future<(bool?, int)> _loadAppSettings() async {
    final db = locator<DatabaseHelper>();

    // Load PIN enabled state from secure storage with DB fallback
    String? pinEnabled;
    try {
      pinEnabled = await _secureStorage.read(key: 'pin_enabled');
    } catch (e) {
      // Secure storage read failed — try DB fallback
      if (kDebugMode) {
        debugPrint('FirstProApp: secure storage read failed: $e');
      }
    }

    if (pinEnabled == null) {
      try {
        pinEnabled = await db.getSetting('pin_enabled');
        if (pinEnabled != null && pinEnabled.isNotEmpty) {
          // Migrate to secure storage
          try {
            await _secureStorage.write(key: 'pin_enabled', value: pinEnabled);
          } catch (_) {}
          await db.deleteSetting('pin_enabled');
        }
      } catch (e) {
        if (kDebugMode) {
          debugPrint('FirstProApp: DB getSetting failed: $e');
        }
      }
    }

    // Load saved theme mode
    int themeMode = 2;
    try {
      final themeModeStr = await db.getSetting('theme_mode_index');
      if (themeModeStr != null) {
        themeMode = int.tryParse(themeModeStr) ?? 2;
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('FirstProApp: theme load failed: $e');
      }
    }

    return (pinEnabled == '1' ? true : (pinEnabled == '0' ? false : null), themeMode);
  }

  /// Whether we can transition away from the splash screen.
  bool get _canTransition => _initComplete && _splashTimerDone;

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
      home: _buildHome(),
      routes: AppRouter.routes,
    );
  }

  Widget _buildHome() {
    // Still showing splash screen (waiting for init + 3s timer)
    if (!_canTransition) {
      return SplashScreen(
        onComplete: () {
          // Splash animation finished — but we still wait for _canTransition
          // This callback is no longer needed since _splashTimerDone handles it
        },
      );
    }

    // Transition ready — show appropriate screen
    // PIN lock enabled → show lock screen first
    if (_pinEnabled == true) {
      return const AppLockScreen();
    }

    // PIN not enabled → go directly to main app
    return const MainScaffold();
  }
}
