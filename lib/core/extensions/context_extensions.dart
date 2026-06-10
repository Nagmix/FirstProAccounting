import 'package:flutter/material.dart';

import 'package:firstpro/core/theme/app_colors.dart';

/// Convenient [BuildContext] extensions for accessing theme data,
/// media-query values, and navigation helpers throughout the app.
extension BuildContextExtensions on BuildContext {
  // ══════════════════════════════════════════════════════════════
  //  THEME
  // ══════════════════════════════════════════════════════════════

  /// The current [ThemeData].
  ThemeData get theme => Theme.of(this);

  /// The current [ColorScheme].
  ColorScheme get colorScheme => Theme.of(this).colorScheme;

  /// The current [TextTheme].
  TextTheme get textTheme => Theme.of(this).textTheme;

  /// Whether the current theme brightness is dark.
  bool get isDarkMode => Theme.of(this).brightness == Brightness.dark;

  // ── Adaptive colors ────────────────────────────────────────────

  /// Primary text color adapted to the current brightness.
  Color get textPrimary =>
      isDarkMode ? AppColors.darkTextPrimary : AppColors.textPrimary;

  /// Secondary text color adapted to the current brightness.
  Color get textSecondary =>
      isDarkMode ? AppColors.darkTextSecondary : AppColors.textSecondary;

  /// Background color adapted to the current brightness.
  Color get backgroundColor =>
      isDarkMode ? AppColors.darkBackground : AppColors.background;

  /// Surface color adapted to the current brightness.
  Color get surfaceColor =>
      isDarkMode ? AppColors.darkSurface : AppColors.surface;

  /// Divider color adapted to the current brightness.
  Color get dividerColor =>
      isDarkMode ? AppColors.darkDivider : AppColors.divider;

  // ══════════════════════════════════════════════════════════════
  //  MEDIA QUERY
  // ══════════════════════════════════════════════════════════════

  /// The current [MediaQueryData].
  MediaQueryData get mediaQuery => MediaQuery.of(this);

  /// Screen width in logical pixels.
  double get screenWidth => MediaQuery.sizeOf(this).width;

  /// Screen height in logical pixels.
  double get screenHeight => MediaQuery.sizeOf(this).height;

  /// The current [Size] of the screen.
  Size get screenSize => MediaQuery.sizeOf(this);

  /// The current device pixel ratio.
  double get devicePixelRatio => MediaQuery.devicePixelRatioOf(this);

  /// Top padding (status bar).
  double get paddingTop => MediaQuery.paddingOf(this).top;

  /// Bottom padding (system navigation bar / home indicator).
  double get paddingBottom => MediaQuery.paddingOf(this).bottom;

  /// Combined view padding.
  EdgeInsets get viewPadding => MediaQuery.viewPaddingOf(this);

  /// Current platform Brightness (light / dark).
  Brightness get platformBrightness => MediaQuery.platformBrightnessOf(this);

  // ── Breakpoints ────────────────────────────────────────────────

  /// `true` when the screen width is < 600 (phone).
  bool get isMobile => screenWidth < 600;

  /// `true` when the screen width is ≥ 600 and < 1024 (tablet).
  bool get isTablet => screenWidth >= 600 && screenWidth < 1024;

  /// `true` when the screen width is ≥ 1024 (desktop / large tablet).
  bool get isDesktop => screenWidth >= 1024;

  /// Horizontal margin that increases on larger screens.
  double get responsiveMargin => isDesktop ? 64 : (isTablet ? 32 : 16);

  // ══════════════════════════════════════════════════════════════
  //  NAVIGATION
  // ══════════════════════════════════════════════════════════════

  /// Pops the top route off the navigator stack (if possible).
  void pop<T extends Object?>([T? result]) => Navigator.of(this).pop(result);

  /// Whether the navigator can pop.
  bool get canPop => Navigator.of(this).canPop();

  /// Pushes a named route.
  Future<T?> pushNamed<T extends Object?>(
    String routeName, {
    Object? arguments,
  }) =>
      Navigator.of(this).pushNamed<T>(routeName, arguments: arguments);

  /// Pushes a replacement named route.
  Future<T?> pushReplacementNamed<T extends Object?, TO extends Object?>(
    String routeName, {
    Object? arguments,
    TO? result,
  }) =>
      Navigator.of(this).pushReplacementNamed<T, TO>(
        routeName,
        arguments: arguments,
        result: result,
      );

  // ══════════════════════════════════════════════════════════════
  //  SNACKBAR & OVERLAYS
  // ══════════════════════════════════════════════════════════════

  /// Shows a [SnackBar] with the given [message].
  ScaffoldFeatureController<SnackBar, SnackBarClosedReason> showSnackBar(
    String message, {
    Duration duration = const Duration(seconds: 3),
    SnackBarAction? action,
  }) {
    return ScaffoldMessenger.of(this).showSnackBar(
      SnackBar(
        content: Text(message),
        duration: duration,
        action: action,
      ),
    );
  }

  /// Shows an error [SnackBar] styled with the error color.
  ScaffoldFeatureController<SnackBar, SnackBarClosedReason> showErrorSnackBar(
    String message, {
    Duration duration = const Duration(seconds: 4),
  }) {
    return ScaffoldMessenger.of(this).showSnackBar(
      SnackBar(
        content: Text(message),
        duration: duration,
        backgroundColor: AppColors.error,
      ),
    );
  }

  /// Shows a success [SnackBar] styled with the success color.
  ScaffoldFeatureController<SnackBar, SnackBarClosedReason> showSuccessSnackBar(
    String message, {
    Duration duration = const Duration(seconds: 3),
  }) {
    return ScaffoldMessenger.of(this).showSnackBar(
      SnackBar(
        content: Text(message),
        duration: duration,
        backgroundColor: AppColors.success,
      ),
    );
  }

  // ══════════════════════════════════════════════════════════════
  //  DIALOG
  // ══════════════════════════════════════════════════════════════

  /// Shows a simple alert dialog with a single OK button.
  Future<void> showAlertDialog({
    required String title,
    required String message,
    String okLabel = 'حسناً',
  }) {
    return showDialog(
      context: this,
      builder: (_) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(this).pop(),
            child: Text(okLabel),
          ),
        ],
      ),
    );
  }

  /// Shows a confirmation dialog with confirm / cancel buttons.
  Future<bool> showConfirmDialog({
    required String title,
    required String message,
    String confirmLabel = 'تأكيد',
    String cancelLabel = 'إلغاء',
    Color? confirmColor,
  }) async {
    final result = await showDialog<bool>(
      context: this,
      builder: (_) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(this).pop(false),
            child: Text(cancelLabel),
          ),
          ElevatedButton(
            style: confirmColor != null
                ? ElevatedButton.styleFrom(backgroundColor: confirmColor)
                : null,
            onPressed: () => Navigator.of(this).pop(true),
            child: Text(confirmLabel),
          ),
        ],
      ),
    );
    return result ?? false;
  }

  // ══════════════════════════════════════════════════════════════
  //  FOCUS
  // ══════════════════════════════════════════════════════════════

  /// Unfocuses any focused input field (hides the keyboard).
  void unfocus() => FocusScope.of(this).unfocus();
}
