import 'package:flutter/material.dart';

import 'package:firstpro/core/theme/app_colors.dart';

/// Unified design system for the FirstPro accounting app.
/// Provides consistent spacing, radii, shadows, and shared widget styles.
class DesignSystem {
  DesignSystem._();

  // ══════════════════════════════════════════════════════════════════
  //  SPACING
  // ══════════════════════════════════════════════════════════════════
  static const double spacing4 = 4.0;
  static const double spacing6 = 6.0;
  static const double spacing8 = 8.0;
  static const double spacing10 = 10.0;
  static const double spacing12 = 12.0;
  static const double spacing14 = 14.0;
  static const double spacing16 = 16.0;
  static const double spacing20 = 20.0;
  static const double spacing24 = 24.0;
  static const double spacing28 = 28.0;
  static const double spacing32 = 32.0;
  static const double spacing40 = 40.0;
  static const double spacing48 = 48.0;

  // ══════════════════════════════════════════════════════════════════
  //  BORDER RADIUS
  // ══════════════════════════════════════════════════════════════════
  static const double radius8 = 8.0;
  static const double radius12 = 12.0;
  static const double radius14 = 14.0;
  static const double radius16 = 16.0;
  static const double radius20 = 20.0;
  static const double radius24 = 24.0;
  static const double radius28 = 28.0;

  static const BorderRadius borderRadius8 =
      BorderRadius.all(Radius.circular(8));
  static const BorderRadius borderRadius12 =
      BorderRadius.all(Radius.circular(12));
  static const BorderRadius borderRadius14 =
      BorderRadius.all(Radius.circular(14));
  static const BorderRadius borderRadius16 =
      BorderRadius.all(Radius.circular(16));
  static const BorderRadius borderRadius20 =
      BorderRadius.all(Radius.circular(20));
  static const BorderRadius borderRadius24 =
      BorderRadius.all(Radius.circular(24));

  // ══════════════════════════════════════════════════════════════════
  //  SHADOWS
  // ══════════════════════════════════════════════════════════════════
  static List<BoxShadow> cardShadow({bool isLight = true}) => [
        BoxShadow(
          color: isLight
              ? AppColors.primary.withValues(alpha: 0.06)
              : Colors.black.withValues(alpha: 0.2),
          offset: const Offset(0, 4),
          blurRadius: 16,
          spreadRadius: 0,
        ),
      ];

  static List<BoxShadow> elevatedShadow({bool isLight = true}) => [
        BoxShadow(
          color: isLight
              ? AppColors.primary.withValues(alpha: 0.12)
              : Colors.black.withValues(alpha: 0.3),
          offset: const Offset(0, 8),
          blurRadius: 24,
          spreadRadius: 0,
        ),
      ];

  static List<BoxShadow> fabShadow = [
    BoxShadow(
      color: AppColors.primary.withValues(alpha: 0.4),
      offset: const Offset(0, 8),
      blurRadius: 16,
    ),
  ];

  // ══════════════════════════════════════════════════════════════════
  //  DURATIONS
  // ══════════════════════════════════════════════════════════════════
  static const Duration animFast = Duration(milliseconds: 200);
  static const Duration animMedium = Duration(milliseconds: 350);
  static const Duration animSlow = Duration(milliseconds: 500);
  static const Duration animEntry = Duration(milliseconds: 600);

  // ══════════════════════════════════════════════════════════════════
  //  CURVES
  // ══════════════════════════════════════════════════════════════════
  static const Curve curveEntry = Curves.fastOutSlowIn;
  static const Curve curveEmphasize = Curves.easeInOutCubicEmphasized;
  static const Curve curveDecelerate = Curves.decelerate;

  // ══════════════════════════════════════════════════════════════════
  //  GRADIENT DECORATIONS
  // ══════════════════════════════════════════════════════════════════
  static BoxDecoration headerGradientDecoration({double radius = 0}) {
    return BoxDecoration(
      gradient: const LinearGradient(
        colors: [AppColors.primaryGradientStart, AppColors.primaryGradientEnd],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      ),
      borderRadius: BorderRadius.vertical(
        bottom: Radius.circular(radius > 0 ? radius : 28),
      ),
    );
  }

  static BoxDecoration circleGradientDecoration({double size = 56}) {
    return BoxDecoration(
      gradient: const LinearGradient(
        colors: [AppColors.primaryGradientStart, AppColors.primaryGradientEnd],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      ),
      shape: BoxShape.circle,
      boxShadow: fabShadow,
    );
  }

  // ══════════════════════════════════════════════════════════════════
  //  ASYMMETRIC BORDER RADIUS (inspired by fitness app)
  // ══════════════════════════════════════════════════════════════════
  static BorderRadius asymmetricTopRight(
      {double large = 68, double small = 12}) {
    return BorderRadius.only(
      topLeft: Radius.circular(small),
      topRight: Radius.circular(large),
      bottomLeft: Radius.circular(small),
      bottomRight: Radius.circular(small),
    );
  }

  // ══════════════════════════════════════════════════════════════════
  //  ACCENT BAR (vertical colored bar for stat items)
  // ══════════════════════════════════════════════════════════════════
  static Widget accentBar({
    required Color color,
    double width = 3,
    double height = 40,
  }) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(4),
      ),
    );
  }

  // ══════════════════════════════════════════════════════════════════
  //  PROGRESS BAR
  // ══════════════════════════════════════════════════════════════════
  static Widget progressBar({
    required double progress,
    required Color color,
    double width = 70,
    double height = 4,
  }) {
    return Container(
      height: height,
      width: width,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Row(
        children: [
          Container(
            width: (width * progress.clamp(0.0, 1.0)),
            height: height,
            decoration: BoxDecoration(
              gradient: LinearGradient(colors: [
                color.withValues(alpha: 0.1),
                color,
              ]),
              borderRadius: BorderRadius.circular(4),
            ),
          ),
        ],
      ),
    );
  }

  // ══════════════════════════════════════════════════════════════════
  //  SECTION DIVIDER
  // ══════════════════════════════════════════════════════════════════
  static Widget sectionDivider({bool isLight = true}) {
    return Container(
      height: 2,
      decoration: BoxDecoration(
        color: isLight ? AppColors.background : AppColors.darkSurfaceVariant,
        borderRadius: BorderRadius.circular(4),
      ),
    );
  }
}
