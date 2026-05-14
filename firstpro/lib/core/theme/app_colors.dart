import 'package:flutter/material.dart';

/// Color constants for the FirstPro accounting app.
/// Modern indigo-blue palette for a professional, contemporary look.
class AppColors {
  AppColors._();

  // ── Primary (Deep Indigo) ──────────────────────────────────────
  static const Color primary = Color(0xFF1A237E);
  static const Color primaryLight = Color(0xFF3949AB);
  static const Color primaryDark = Color(0xFF0D1442);

  // ── Secondary (Amber/Gold) ──────────────────────────────────────
  static const Color secondary = Color(0xFFFFB300);
  static const Color secondaryLight = Color(0xFFFFD54F);
  static const Color secondaryDark = Color(0xFFFF8F00);

  // ── Accent ────────────────────────────────────────────────────
  static const Color accent = Color(0xFF5C6BC0);

  // ── Light theme surfaces ──────────────────────────────────────
  static const Color background = Color(0xFFF5F6FA);
  static const Color surface = Color(0xFFFFFFFF);
  static const Color surfaceVariant = Color(0xFFEEF0F6);

  // ── Semantic / status ─────────────────────────────────────────
  static const Color error = Color(0xFFE53935);
  static const Color errorLight = Color(0xFFFFCDD2);
  static const Color warning = Color(0xFFFF9800);
  static const Color warningLight = Color(0xFFFFE0B2);
  static const Color success = Color(0xFF43A047);
  static const Color successLight = Color(0xFFC8E6C9);
  static const Color info = Color(0xFF1E88E5);
  static const Color infoLight = Color(0xFFBBDEFB);

  // ── Text ──────────────────────────────────────────────────────
  static const Color textPrimary = Color(0xFF1A1A2E);
  static const Color textSecondary = Color(0xFF6B7280);
  static const Color textHint = Color(0xFF9CA3AF);
  static const Color textDisabled = Color(0xFFBDBDBD);

  // ── Dividers & borders ────────────────────────────────────────
  static const Color divider = Color(0xFFE5E7EB);
  static const Color border = Color(0xFFE5E7EB);

  // ── Dark theme ────────────────────────────────────────────────
  static const Color darkBackground = Color(0xFF0F0F1A);
  static const Color darkSurface = Color(0xFF1A1A2E);
  static const Color darkSurfaceVariant = Color(0xFF262640);
  static const Color darkTextPrimary = Color(0xFFE8E8F0);
  static const Color darkTextSecondary = Color(0xFF9CA3AF);
  static const Color darkDivider = Color(0xFF3A3A5C);
  static const Color darkBorder = Color(0xFF3A3A5C);
}
