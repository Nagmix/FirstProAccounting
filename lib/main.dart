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
import 'package:firstpro/data/datasources/database_helper.dart';
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

  /// Theme mode loaded from settings: 0=light, 1=dark, 2=system
  int _themeModeIndex = 2; // Default to system

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
    int themeMode = 2;

    try {
      // Initialize dynamic currency constants
      await CurrencyConstants.refresh();

      // Initialize license service alongside other inits
      final settingsResult = await _loadAppSettings().timeout(
        const Duration(seconds: 5),
        onTimeout: () => (null, 2),
      );
      await _licenseProvider.initialize().timeout(
            const Duration(seconds: 8),
            onTimeout: () {},
          );

      pinEnabled = settingsResult.$1;
      themeMode = settingsResult.$2;
    } catch (e) {
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
  Future<(bool?, int)> _loadAppSettings() async {
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

    int themeMode = 2;
    try {
      final themeModeStr = await db.getSetting('theme_mode_index');
      if (themeModeStr != null) {
        themeMode = int.tryParse(themeModeStr) ?? 2;
      }
    } catch (e) {
      if (kDebugMode) debugPrint('FirstProApp: theme load failed: $e');
    }

    return (
      pinEnabled == '1' ? true : (pinEnabled == '0' ? false : null),
      themeMode
    );
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
    return ChangeNotifierProvider<LicenseProvider>.value(
      value: _licenseProvider,
      child: MaterialApp(
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
        themeMode: _getThemeMode(),
        home: _buildHome(),
        routes: AppRouter.routes,
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
