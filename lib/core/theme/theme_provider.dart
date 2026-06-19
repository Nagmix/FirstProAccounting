import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:firstpro/core/di/service_locator.dart';
import 'package:firstpro/data/datasources/repositories/reference_data_repository.dart';

/// Centralized, reactive theme-mode controller for the whole app.
///
/// Why this exists (audit U-01):
///   Before this class, `theme_mode_index` was loaded once at app startup in
///   `main.dart`'s `_FirstProAppState._startInit()` and stored in a local
///   `int _themeModeIndex` field. Changing the theme from `SettingsScreen`
///   wrote the new value to the DB but `MaterialApp.themeMode` was NOT
///   reactive — the new theme only took effect after a full app restart,
///   which is a poor UX.
///
///   `ThemeProvider` is a `ChangeNotifier` registered as a lazy singleton in
///   `service_locator.dart`. `main.dart` listens to it via
///   `ChangeNotifierProvider` / `ListenableBuilder` and rebuilds
///   `MaterialApp` whenever the theme mode changes. `SettingsScreen` calls
///   `setThemeMode(int)` which both persists to DB and notifies listeners,
///   so the new theme applies instantly with no restart.
///
/// Storage:
///   - DB `settings` table key `theme_mode_index` (canonical source).
///   - Values: 0 = light, 1 = dark, 2 = system (default).
class ThemeProvider extends ChangeNotifier {
  ThemeProvider();

  int _themeModeIndex = 2; // default to system
  bool _initialized = false;

  /// Current theme mode index. 0=light, 1=dark, 2=system.
  int get themeModeIndex => _themeModeIndex;

  /// Current [ThemeMode] for [MaterialApp.themeMode].
  ThemeMode get themeMode {
    switch (_themeModeIndex) {
      case 0:
        return ThemeMode.light;
      case 1:
        return ThemeMode.dark;
      default:
        return ThemeMode.system;
    }
  }

  /// Whether [initialize] has been called at least once.
  bool get isInitialized => _initialized;

  /// Load the persisted theme mode from the DB settings table.
  ///
  /// Called once at app startup from `main.dart`. Safe to call multiple
  /// times; subsequent calls reload the value from DB and notify listeners
  /// if it changed (e.g. if the setting was changed from another isolate
  /// or restored from backup).
  Future<void> initialize() async {
    int themeMode = 2;
    try {
      final refRepo = locator<ReferenceDataRepository>();
      final stored = await refRepo.getSetting('theme_mode_index');
      if (stored != null && stored.isNotEmpty) {
        themeMode = int.tryParse(stored) ?? 2;
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('ThemeProvider.initialize: $e');
      }
    }
    if (themeMode != _themeModeIndex || !_initialized) {
      _themeModeIndex = themeMode;
      _initialized = true;
      notifyListeners();
    } else {
      _initialized = true;
    }
  }

  /// Set a new theme mode. Persists to DB immediately and notifies
  /// listeners so `MaterialApp` rebuilds with the new [ThemeMode].
  ///
  /// [index] must be 0 (light), 1 (dark), or 2 (system). Any other value
  /// is silently clamped to 2 (system) for safety.
  Future<void> setThemeMode(int index) async {
    final clamped = (index == 0 || index == 1) ? index : 2;
    if (clamped == _themeModeIndex) return;
    _themeModeIndex = clamped;
    notifyListeners();
    try {
      final refRepo = locator<ReferenceDataRepository>();
      await refRepo.setSetting('theme_mode_index', clamped.toString());
    } catch (e) {
      if (kDebugMode) {
        debugPrint('ThemeProvider.setThemeMode persist failed: $e');
      }
      // The in-memory state is already updated; DB write failure is
      // non-fatal — the next app restart will fall back to the previous
      // persisted value.
    }
  }
}
