import 'package:flutter/material.dart';

/// Color constants for the FirstPro accounting app.
/// Provides a unified color palette for both light and dark themes.
class AppColors {
  AppColors._();

  // ── Primary (Deep Green) ──────────────────────────────────────
  static const Color primary = Color(0xFF1B5E20);
  static const Color primaryLight = Color(0xFF2E7D32);
  static const Color primaryDark = Color(0xFF0D3B0F);

  // ── Secondary (Gold) ──────────────────────────────────────────
  static const Color secondary = Color(0xFFC9A84C);
  static const Color secondaryLight = Color(0xFFD4BC6A);
  static const Color secondaryDark = Color(0xFFA68B34);

  // ── Accent ────────────────────────────────────────────────────
  static const Color accent = Color(0xFF4CAF50);

  // ── Light theme surfaces ──────────────────────────────────────
  static const Color background = Color(0xFFFAFAFA);
  static const Color surface = Color(0xFFFFFFFF);
  static const Color surfaceVariant = Color(0xFFF5F5F5);

  // ── Semantic / status ─────────────────────────────────────────
  static const Color error = Color(0xFFF44336);
  static const Color errorLight = Color(0xFFFFCDD2);
  static const Color warning = Color(0xFFFF9800);
  static const Color warningLight = Color(0xFFFFE0B2);
  static const Color success = Color(0xFF4CAF50);
  static const Color successLight = Color(0xFFC8E6C9);
  static const Color info = Color(0xFF2196F3);
  static const Color infoLight = Color(0xFFBBDEFB);

  // ── Text ──────────────────────────────────────────────────────
  static const Color textPrimary = Color(0xFF212121);
  static const Color textSecondary = Color(0xFF757575);
  static const Color textHint = Color(0xFF9E9E9E);
  static const Color textDisabled = Color(0xFFBDBDBD);

  // ── Dividers & borders ────────────────────────────────────────
  static const Color divider = Color(0xFFE0E0E0);
  static const Color border = Color(0xFFE0E0E0);

  // ── Dark theme ────────────────────────────────────────────────
  static const Color darkBackground = Color(0xFF121212);
  static const Color darkSurface = Color(0xFF1E1E1E);
  static const Color darkSurfaceVariant = Color(0xFF2C2C2C);
  static const Color darkTextPrimary = Color(0xFFE0E0E0);
  static const Color darkTextSecondary = Color(0xFF9E9E9E);
  static const Color darkDivider = Color(0xFF424242);
  static const Color darkBorder = Color(0xFF424242);
}
