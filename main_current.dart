import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'core/constants/app_constants.dart';
import 'core/theme/app_theme.dart';
import 'ui/navigation/app_router.dart';
import 'ui/navigation/main_scaffold.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();

  // Set preferred orientations for a typical accounting app (portrait-first).
  // SystemChrome.setPreferredOrientations can be added here if needed.

  runApp(const FirstProApp());
}

/// Root widget for the FirstPro accounting application.
class FirstProApp extends StatelessWidget {
  const FirstProApp({super.key});

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
      home: const MainScaffold(),
      routes: AppRouter.routes,
    );
  }
}
