import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app_colors.dart';

/// Comprehensive Material 3 theme for the FirstPro accounting app.
/// Modern 2026 design with deep blue-purple gradients, smooth shadows,
/// and refined typography using Cairo for Arabic RTL support.
class AppTheme {
  AppTheme._();

  // ── Seed color for Material 3 ColorScheme ─────────────────────────
  static const Color _seedColor = AppColors.primary;

  // ══════════════════════════════════════════════════════════════════
  //  LIGHT THEME
  // ══════════════════════════════════════════════════════════════════
  static ThemeData get lightTheme {
    final colorScheme = ColorScheme.fromSeed(
      seedColor: _seedColor,
      brightness: Brightness.light,
      primary: AppColors.primary,
      secondary: AppColors.secondary,
      surface: AppColors.surface,
      error: AppColors.error,
    );

    return _buildThemeData(
      colorScheme: colorScheme,
      brightness: Brightness.light,
    );
  }

  // ══════════════════════════════════════════════════════════════════
  //  DARK THEME
  // ══════════════════════════════════════════════════════════════════
  static ThemeData get darkTheme {
    final colorScheme = ColorScheme.fromSeed(
      seedColor: _seedColor,
      brightness: Brightness.dark,
      primary: AppColors.primaryLight,
      secondary: AppColors.secondaryLight,
      surface: AppColors.darkSurface,
      error: AppColors.error,
    );

    return _buildThemeData(
      colorScheme: colorScheme,
      brightness: Brightness.dark,
    );
  }

  // ══════════════════════════════════════════════════════════════════
  //  SHARED BUILDER
  // ══════════════════════════════════════════════════════════════════
  static ThemeData _buildThemeData({
    required ColorScheme colorScheme,
    required Brightness brightness,
  }) {
    final isLight = brightness == Brightness.light;
    final textTheme = _buildTextTheme(brightness);

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: colorScheme,
      textTheme: textTheme,

      // ── Scaffold ──────────────────────────────────────────────
      scaffoldBackgroundColor:
          isLight ? AppColors.background : AppColors.darkBackground,

      // ── AppBar ────────────────────────────────────────────────
      appBarTheme: AppBarTheme(
        centerTitle: true,
        elevation: 0,
        scrolledUnderElevation: 0,
        backgroundColor: Colors.transparent,
        foregroundColor: isLight ? AppColors.textPrimary : AppColors.darkTextPrimary,
        titleTextStyle: textTheme.titleLarge?.copyWith(
          color: isLight ? AppColors.textPrimary : AppColors.darkTextPrimary,
          fontWeight: FontWeight.w700,
          letterSpacing: 0,
        ),
        systemOverlayStyle: SystemUiOverlayStyle(
          statusBarColor: Colors.transparent,
          statusBarIconBrightness:
              isLight ? Brightness.dark : Brightness.light,
          statusBarBrightness:
              isLight ? Brightness.dark : Brightness.dark,
        ),
      ),

      // ── Card ──────────────────────────────────────────────────
      cardTheme: CardThemeData(
        elevation: 2,
        shadowColor: isLight
            ? AppColors.primary.withValues(alpha: 0.08)
            : Colors.black.withValues(alpha: 0.3),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        color: isLight ? AppColors.surface : AppColors.darkSurface,
        surfaceTintColor: Colors.transparent,
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      ),

      // ── Floating Action Button ────────────────────────────────
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        elevation: 6,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        extendedTextStyle: textTheme.labelLarge?.copyWith(
          fontWeight: FontWeight.w700,
          letterSpacing: 0,
        ),
      ),

      // ── Bottom Navigation Bar ─────────────────────────────────
      bottomNavigationBarTheme: BottomNavigationBarThemeData(
        backgroundColor:
            isLight ? AppColors.surface : AppColors.darkSurface,
        selectedItemColor: AppColors.primary,
        unselectedItemColor:
            isLight ? AppColors.textSecondary : AppColors.darkTextSecondary,
        type: BottomNavigationBarType.fixed,
        elevation: 0,
        selectedLabelStyle: textTheme.labelSmall?.copyWith(
          fontWeight: FontWeight.w700,
        ),
        unselectedLabelStyle: textTheme.labelSmall?.copyWith(
          fontWeight: FontWeight.w500,
        ),
      ),

      // ── Navigation Bar (M3) ───────────────────────────────────
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor:
            isLight ? AppColors.surface : AppColors.darkSurface,
        indicatorColor: AppColors.primary.withValues(alpha: 0.12),
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return textTheme.labelSmall?.copyWith(
              color: AppColors.primary,
              fontWeight: FontWeight.w700,
            );
          }
          return textTheme.labelSmall?.copyWith(
            color: isLight
                ? AppColors.textSecondary
                : AppColors.darkTextSecondary,
            fontWeight: FontWeight.w500,
          );
        }),
      ),

      // ── Input Decoration ──────────────────────────────────────
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: isLight
            ? AppColors.surfaceVariant
            : AppColors.darkSurfaceVariant,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(
            color: AppColors.primary,
            width: 2,
          ),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(
            color: AppColors.error,
            width: 1.5,
          ),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(
            color: AppColors.error,
            width: 2,
          ),
        ),
        labelStyle: textTheme.bodyMedium?.copyWith(
          color: isLight ? AppColors.textSecondary : AppColors.darkTextSecondary,
        ),
        hintStyle: textTheme.bodyMedium?.copyWith(
          color: isLight ? AppColors.textHint : AppColors.darkTextSecondary,
        ),
        prefixIconColor: WidgetStateColor.resolveWith((states) {
          if (states.contains(WidgetState.focused)) {
            return AppColors.primary;
          }
          if (states.contains(WidgetState.error)) {
            return AppColors.error;
          }
          return isLight ? AppColors.textHint : AppColors.darkTextSecondary;
        }),
        suffixIconColor: WidgetStateColor.resolveWith((states) {
          if (states.contains(WidgetState.focused)) {
            return AppColors.primary;
          }
          if (states.contains(WidgetState.error)) {
            return AppColors.error;
          }
          return isLight ? AppColors.textHint : AppColors.darkTextSecondary;
        }),
      ),

      // ── Elevated Button ───────────────────────────────────────
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.primary,
          foregroundColor: Colors.white,
          elevation: 2,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          textStyle: textTheme.labelLarge?.copyWith(
            fontWeight: FontWeight.w700,
            letterSpacing: 0,
          ),
        ),
      ),

      // ── Outlined Button ───────────────────────────────────────
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.primary,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          side: const BorderSide(color: AppColors.primary, width: 1.5),
          textStyle: textTheme.labelLarge?.copyWith(
            fontWeight: FontWeight.w700,
            letterSpacing: 0,
          ),
        ),
      ),

      // ── Text Button ───────────────────────────────────────────
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: AppColors.primary,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
          ),
          textStyle: textTheme.labelLarge?.copyWith(
            fontWeight: FontWeight.w600,
            letterSpacing: 0,
          ),
        ),
      ),

      // ── Icon Button ───────────────────────────────────────────
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(
          foregroundColor:
              isLight ? AppColors.textPrimary : AppColors.darkTextPrimary,
          iconSize: 24,
          padding: const EdgeInsets.all(8),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
        ),
      ),

      // ── Chip ──────────────────────────────────────────────────
      chipTheme: ChipThemeData(
        backgroundColor:
            isLight ? AppColors.surfaceVariant : AppColors.darkSurfaceVariant,
        selectedColor: AppColors.primary.withValues(alpha: 0.12),
        labelStyle: textTheme.bodySmall?.copyWith(
          fontWeight: FontWeight.w600,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
        ),
        side: BorderSide.none,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      ),

      // ── Divider ───────────────────────────────────────────────
      dividerTheme: DividerThemeData(
        color: isLight ? AppColors.divider : AppColors.darkDivider,
        thickness: 1,
        space: 1,
      ),

      // ── Dialog ────────────────────────────────────────────────
      dialogTheme: DialogThemeData(
        backgroundColor:
            isLight ? AppColors.surface : AppColors.darkSurface,
        elevation: 8,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
        ),
        titleTextStyle: textTheme.titleLarge?.copyWith(
          fontWeight: FontWeight.w700,
          color: isLight ? AppColors.textPrimary : AppColors.darkTextPrimary,
        ),
      ),

      // ── SnackBar ──────────────────────────────────────────────
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
        backgroundColor:
            isLight ? AppColors.textPrimary : AppColors.darkTextPrimary,
        contentTextStyle: textTheme.bodyMedium?.copyWith(
          color: isLight ? Colors.white : Colors.black,
        ),
      ),

      // ── Bottom Sheet ──────────────────────────────────────────
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor:
            isLight ? AppColors.surface : AppColors.darkSurface,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        showDragHandle: true,
      ),

      // ── Tab Bar ───────────────────────────────────────────────
      tabBarTheme: TabBarThemeData(
        labelColor: isLight ? AppColors.primary : AppColors.primaryLight,
        unselectedLabelColor:
            isLight ? AppColors.textSecondary : AppColors.darkTextSecondary,
        labelStyle: textTheme.labelLarge?.copyWith(
          fontWeight: FontWeight.w700,
        ),
        unselectedLabelStyle: textTheme.labelLarge?.copyWith(
          fontWeight: FontWeight.w500,
        ),
        indicatorColor: AppColors.secondary,
        indicatorSize: TabBarIndicatorSize.label,
      ),

      // ── List Tile ─────────────────────────────────────────────
      listTileTheme: ListTileThemeData(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16),
        titleTextStyle: textTheme.bodyLarge?.copyWith(
          fontWeight: FontWeight.w600,
          color: isLight ? AppColors.textPrimary : AppColors.darkTextPrimary,
        ),
        subtitleTextStyle: textTheme.bodySmall?.copyWith(
          color: isLight
              ? AppColors.textSecondary
              : AppColors.darkTextSecondary,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
      ),

      // ── Switch ────────────────────────────────────────────────
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return AppColors.primary;
          }
          return isLight ? Colors.white : AppColors.darkTextSecondary;
        }),
        trackColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return AppColors.primary.withValues(alpha: 0.5);
          }
          return isLight ? AppColors.divider : AppColors.darkDivider;
        }),
      ),

      // ── Checkbox ──────────────────────────────────────────────
      checkboxTheme: CheckboxThemeData(
        fillColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return AppColors.primary;
          }
          return Colors.transparent;
        }),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(4),
        ),
      ),

      // ── Progress Indicator ────────────────────────────────────
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: AppColors.primary,
        linearTrackColor:
            isLight ? AppColors.divider : AppColors.darkDivider,
        circularTrackColor:
            isLight ? AppColors.divider : AppColors.darkDivider,
      ),

      // ── Tooltip ───────────────────────────────────────────────
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
          color: isLight
              ? AppColors.textPrimary
              : AppColors.darkTextPrimary,
          borderRadius: BorderRadius.circular(8),
        ),
        textStyle: textTheme.bodySmall?.copyWith(
          color: isLight ? Colors.white : Colors.black,
        ),
        waitDuration: const Duration(milliseconds: 500),
      ),

      // ── Popup Menu ────────────────────────────────────────────
      popupMenuTheme: PopupMenuThemeData(
        color: isLight ? AppColors.surface : AppColors.darkSurface,
        elevation: 8,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
        textStyle: textTheme.bodyMedium?.copyWith(
          color: isLight ? AppColors.textPrimary : AppColors.darkTextPrimary,
        ),
      ),

      // ── Search Bar ────────────────────────────────────────────
      searchBarTheme: SearchBarThemeData(
        elevation: WidgetStateProperty.all(0),
        shape: WidgetStateProperty.all(
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
        backgroundColor: WidgetStateProperty.all(
          isLight ? AppColors.surfaceVariant : AppColors.darkSurfaceVariant,
        ),
        hintStyle: WidgetStateProperty.all(
          textTheme.bodyMedium?.copyWith(
            color: isLight ? AppColors.textHint : AppColors.darkTextSecondary,
          ),
        ),
      ),

      // ── Drawer ────────────────────────────────────────────────
      drawerTheme: DrawerThemeData(
        backgroundColor:
            isLight ? AppColors.surface : AppColors.darkSurface,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.horizontal(
            left: Radius.circular(24),
          ),
        ),
      ),
    );
  }

  // ══════════════════════════════════════════════════════════════════
  //  TEXT THEME – all styles include fontFamily: 'Cairo'
  // ══════════════════════════════════════════════════════════════════
  static TextTheme _buildTextTheme(Brightness brightness) {
    final baseColor =
        brightness == Brightness.light
            ? AppColors.textPrimary
            : AppColors.darkTextPrimary;
    final secondaryColor =
        brightness == Brightness.light
            ? AppColors.textSecondary
            : AppColors.darkTextSecondary;

    const fontFamily = 'Cairo';

    return TextTheme(
      displayLarge: TextStyle(
        fontFamily: fontFamily, fontSize: 57,
        fontWeight: FontWeight.w400,
        height: 1.12,
        letterSpacing: -0.25,
        color: baseColor,
      ),
      displayMedium: TextStyle(
        fontFamily: fontFamily, fontSize: 45,
        fontWeight: FontWeight.w400,
        height: 1.16,
        letterSpacing: 0,
        color: baseColor,
      ),
      displaySmall: TextStyle(
        fontFamily: fontFamily, fontSize: 36,
        fontWeight: FontWeight.w400,
        height: 1.22,
        letterSpacing: 0,
        color: baseColor,
      ),
      headlineLarge: TextStyle(
        fontFamily: fontFamily, fontSize: 32,
        fontWeight: FontWeight.w600,
        height: 1.25,
        letterSpacing: 0,
        color: baseColor,
      ),
      headlineMedium: TextStyle(
        fontFamily: fontFamily, fontSize: 28,
        fontWeight: FontWeight.w600,
        height: 1.29,
        letterSpacing: 0,
        color: baseColor,
      ),
      headlineSmall: TextStyle(
        fontFamily: fontFamily, fontSize: 24,
        fontWeight: FontWeight.w600,
        height: 1.33,
        letterSpacing: 0,
        color: baseColor,
      ),
      titleLarge: TextStyle(
        fontFamily: fontFamily, fontSize: 22,
        fontWeight: FontWeight.w700,
        height: 1.27,
        letterSpacing: 0,
        color: baseColor,
      ),
      titleMedium: TextStyle(
        fontFamily: fontFamily, fontSize: 16,
        fontWeight: FontWeight.w600,
        height: 1.50,
        letterSpacing: 0.15,
        color: baseColor,
      ),
      titleSmall: TextStyle(
        fontFamily: fontFamily, fontSize: 14,
        fontWeight: FontWeight.w600,
        height: 1.43,
        letterSpacing: 0.1,
        color: baseColor,
      ),
      bodyLarge: TextStyle(
        fontFamily: fontFamily, fontSize: 16,
        fontWeight: FontWeight.w400,
        height: 1.50,
        letterSpacing: 0.5,
        color: baseColor,
      ),
      bodyMedium: TextStyle(
        fontFamily: fontFamily, fontSize: 14,
        fontWeight: FontWeight.w400,
        height: 1.43,
        letterSpacing: 0.25,
        color: baseColor,
      ),
      bodySmall: TextStyle(
        fontFamily: fontFamily, fontSize: 12,
        fontWeight: FontWeight.w400,
        height: 1.33,
        letterSpacing: 0.4,
        color: secondaryColor,
      ),
      labelLarge: TextStyle(
        fontFamily: fontFamily, fontSize: 14,
        fontWeight: FontWeight.w600,
        height: 1.43,
        letterSpacing: 0.1,
        color: baseColor,
      ),
      labelMedium: TextStyle(
        fontFamily: fontFamily, fontSize: 12,
        fontWeight: FontWeight.w600,
        height: 1.33,
        letterSpacing: 0.5,
        color: secondaryColor,
      ),
      labelSmall: TextStyle(
        fontFamily: fontFamily, fontSize: 11,
        fontWeight: FontWeight.w500,
        height: 1.45,
        letterSpacing: 0.5,
        color: secondaryColor,
      ),
    );
  }
}
