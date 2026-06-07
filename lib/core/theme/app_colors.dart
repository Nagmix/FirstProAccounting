import 'package:flutter/material.dart';

/// Modern color palette for the FirstPro accounting app.
/// Inspired by 2026 design trends with deep blue-purple gradients,
/// warm amber accents, and clean surface colors.
class AppColors {
  AppColors._();

  // ── Primary (Deep Blue-Purple Gradient) ──────────────────────────
  static const Color primary = Color(0xFF2633C5);
  static const Color primaryLight = Color(0xFF6A88E5);
  static const Color primaryDark = Color(0xFF1A237E);
  static const Color primaryGradientStart = Color(0xFF2633C5);
  static const Color primaryGradientEnd = Color(0xFF6A88E5);

  // ── Secondary (Warm Amber/Gold) ──────────────────────────────────
  static const Color secondary = Color(0xFFF1B440);
  static const Color secondaryLight = Color(0xFFFFD54F);
  static const Color secondaryDark = Color(0xFFFF8F00);

  // ── Accent Colors ────────────────────────────────────────────────
  static const Color accentBlue = Color(0xFF87A0E5);
  static const Color accentPink = Color(0xFFF56E98);
  static const Color accentPurple = Color(0xFF9C27B0);

  // ── Light theme surfaces ─────────────────────────────────────────
  static const Color background = Color(0xFFF2F3F8);
  static const Color lightBackground = Color(0xFFF2F3F8);
  static const Color surface = Color(0xFFFFFFFF);
  static const Color surfaceVariant = Color(0xFFF5F6FA);

  // ── Semantic / status ────────────────────────────────────────────
  static const Color error = Color(0xFFE53935);
  static const Color errorLight = Color(0xFFFFCDD2);
  static const Color warning = Color(0xFFFF9800);
  static const Color warningLight = Color(0xFFFFE0B2);
  static const Color success = Color(0xFF43A047);
  static const Color successLight = Color(0xFFC8E6C9);
  static const Color info = Color(0xFF1E88E5);
  static const Color infoLight = Color(0xFFBBDEFB);

  // ── Text ─────────────────────────────────────────────────────────
  static const Color textPrimary = Color(0xFF17262A);
  static const Color textSecondary = Color(0xFF4A6572);
  static const Color textTertiary = Color(0xFF9E9E9E);
  static const Color textHint = Color(0xFF767676);
  static const Color textDisabled = Color(0xFFBDBDBD);
  static const Color darkText = Color(0xFF253840);
  static const Color darkerText = Color(0xFF17262A);

  // ── Dividers & borders ───────────────────────────────────────────
  static const Color divider = Color(0xFFE5E7EB);
  static const Color border = Color(0xFFE5E7EB);
  static const Color spacer = Color(0xFFF2F2F2);

  // ── Dark theme ───────────────────────────────────────────────────
  static const Color darkBackground = Color(0xFF0F0F1A);
  static const Color darkSurface = Color(0xFF1A1A2E);
  static const Color darkSurfaceVariant = Color(0xFF262640);
  static const Color darkTextPrimary = Color(0xFFE8E8F0);
  static const Color darkTextSecondary = Color(0xFF9CA3AF);
  static const Color darkTextTertiary = Color(0xFF6B7280);
  static const Color darkDivider = Color(0xFF3A3A5C);
  static const Color darkBorder = Color(0xFF3A3A5C);

  // ── Gradients ────────────────────────────────────────────────────
  static const LinearGradient primaryGradient = LinearGradient(
    colors: [primaryGradientStart, primaryGradientEnd],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient primaryGradientVertical = LinearGradient(
    colors: [primaryGradientStart, primaryGradientEnd],
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
  );

  static const LinearGradient accentGradient = LinearGradient(
    colors: [accentBlue, primaryLight],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  // ── Chart / Data Visualization Colors ────────────────────────────
  static const List<Color> chartColors = [
    accentBlue,
    accentPink,
    secondary,
    success,
    primary,
    warning,
  ];
}
