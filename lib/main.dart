import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:provider/provider.dart';

import 'package:firstpro/l10n/generated/app_localizations.dart';
import 'package:firstpro/core/constants/app_constants.dart';
import 'package:firstpro/core/helpers/currency_constants.dart';
import 'package:firstpro/core/di/service_locator.dart';
import 'package:firstpro/core/license/license_provider.dart';
import 'package:firstpro/core/license/license_models.dart';
import 'package:firstpro/core/theme/app_theme.dart';
import 'package:firstpro/core/theme/theme_provider.dart';
import 'package:firstpro/data/datasources/database_helper.dart';
import 'package:firstpro/data/datasources/services/inventory_alert_service.dart';
import 'package:firstpro/ui/navigation/app_router.dart';
import 'package:firstpro/ui/navigation/main_scaffold.dart';
import 'package:firstpro/ui/screens/app_lock/app_lock_screen.dart';
import 'package:firstpro/ui/screens/license/license_activation_screen.dart';
import 'package:firstpro/ui/screens/license/license_expiry_screen.dart';
import 'package:firstpro/ui/screens/splash/splash_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await setupLocator();

  runApp(const FirstProApp());
}

/// Root widget for the FirstPro accounting application.
class FirstProApp extends StatefulWidget {
  const FirstProApp({super.key});

  @override
  State<FirstProApp> createState() => _FirstProAppState();
}

class _FirstProAppState extends State<FirstProApp> {
  /// null = still on splash, true = PIN enabled, false = PIN disabled
  bool? _pinEnabled;

  /// Theme provider (app-wide, reactive). Initialized in [_startInit] via
  /// `locator<ThemeProvider>().initialize()`. The MaterialApp listens to it
  /// via ChangeNotifierProvider so theme changes from SettingsScreen apply
  /// instantly without an app restart (audit U-01 fix).
  final ThemeProvider _themeProvider = locator<ThemeProvider>();

  /// Whether initialization is complete (splash can transition)
  bool _initComplete = false;

  /// Whether splash timer has elapsed (3 seconds)
  bool _splashTimerDone = false;

  /// License provider instance
  final LicenseProvider _licenseProvider = LicenseProvider();

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

    try {
      // Initialize dynamic currency constants
      await CurrencyConstants.refresh();

      // Initialize theme provider (loads theme_mode_index from DB)
      await _themeProvider.initialize().timeout(
            const Duration(seconds: 3),
            onTimeout: () {},
          );

      // Load PIN state from secure storage / DB
      pinEnabled = await _loadPinState().timeout(
            const Duration(seconds: 5),
            onTimeout: () => null,
          );

      // Initialize license service
      await _licenseProvider.initialize().timeout(
            const Duration(seconds: 8),
            onTimeout: () {},
          );

      // F-05 + F-06: scan inventory for low-stock and expiry alerts.
      // Run in the background (fire-and-forget) — must NOT block the
      // splash transition. Errors are caught and printed (non-critical).
      // The scan is idempotent: only NEW alerts are inserted.
      _runInventoryAlertScan();
    } catch (e) {
      if (kDebugMode) {
        debugPrint('FirstProApp._startInit: $e');
      }
    }

    if (mounted) {
      setState(() {
        _pinEnabled = pinEnabled;
        _initComplete = true;
      });
    }
  }

  /// F-05 + F-06: run the inventory alert scan in the background.
  ///
  /// Fire-and-forget — does NOT block the splash transition. The scan
  /// is idempotent (only inserts NEW alerts; skips ones that already
  /// exist as unread). Errors are caught and printed (non-critical:
  /// alert generation must never prevent the app from launching).
  void _runInventoryAlertScan() {
    Future(() async {
      try {
        final service = locator<InventoryAlertService>();
        await service.scanAndGenerateAlerts();
      } catch (e) {
        if (kDebugMode) {
          debugPrint('FirstProApp._runInventoryAlertScan: $e');
        }
      }
    });
  }

  /// Load PIN state from secure storage (with DB fallback migration).
  /// Theme mode is now loaded by [ThemeProvider.initialize] and is no
  /// longer read here (audit U-01 refactor).
  Future<bool?> _loadPinState() async {
    final db = locator<DatabaseHelper>();

    String? pinEnabled;
    try {
      pinEnabled = await _secureStorage.read(key: 'pin_enabled');
    } catch (e) {
      if (kDebugMode) debugPrint('FirstProApp: secure storage read failed: $e');
    }

    if (pinEnabled == null) {
      try {
        pinEnabled = await db.getSetting('pin_enabled');
        if (pinEnabled != null && pinEnabled.isNotEmpty) {
          try {
            await _secureStorage.write(key: 'pin_enabled', value: pinEnabled);
          } catch (e) {
            // B-8: لا نبتلع الأخطاء بصمت في كود مالي — سجّل ثم تابع المسار الاحتياطي
            debugPrint('تعذر ترحيل pin_enabled إلى التخزين الآمن: $e');
          }
          await db.deleteSetting('pin_enabled');
        }
      } catch (e) {
        if (kDebugMode) debugPrint('FirstProApp: DB getSetting failed: $e');
      }
    }

    return pinEnabled == '1' ? true : (pinEnabled == '0' ? false : null);
  }

  /// Whether we can transition away from the splash screen.
  bool get _canTransition => _initComplete && _splashTimerDone;

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider<LicenseProvider>.value(value: _licenseProvider),
        ChangeNotifierProvider<ThemeProvider>.value(value: _themeProvider),
      ],
      child: ListenableBuilder(
        listenable: _themeProvider,
        builder: (context, _) {
          return MaterialApp(
            title: AppConstants.appName,
            debugShowCheckedModeBanner: false,
            localizationsDelegates: const [
              AppLocalizations.delegate,
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            locale: const Locale('ar'),
            supportedLocales: AppLocalizations.supportedLocales,
            theme: AppTheme.lightTheme,
            darkTheme: AppTheme.darkTheme,
            themeMode: _themeProvider.themeMode,
            home: _buildHome(),
            routes: AppRouter.routes,
          );
        },
      ),
    );
  }

  Widget _buildHome() {
    if (!_canTransition) {
      return const SplashScreen();
    }

    // Check if license is expired or revoked
    final licenseState = _licenseProvider.state;
    if (licenseState.status == LicenseStatus.expired) {
      return const LicenseExpiryScreen();
    }
    if (licenseState.status == LicenseStatus.revoked) {
      return const LicenseActivationScreen();
    }

    // PIN lock enabled → show lock screen first
    if (_pinEnabled == true) {
      return const AppLockScreen();
    }

    // PIN not enabled → go directly to main app
    return const MainScaffold();
  }
}
