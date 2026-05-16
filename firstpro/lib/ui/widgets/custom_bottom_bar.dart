import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/design_system.dart';

/// Custom bottom navigation bar with a notched center for the FAB button.
/// Uses [BottomBarClipper] to create a semicircular notch at the top center
/// where the FAB sits, ensuring proper RTL layout and even item distribution.
class CustomBottomBar extends StatelessWidget {
  const CustomBottomBar({
    super.key,
    required this.selectedIndex,
    required this.onTap,
    required this.onFabTap,
    required this.items,
  });

  final int selectedIndex;
  final ValueChanged<int> onTap;
  final VoidCallback onFabTap;
  final List<CustomBottomBarItem> items;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final bottomPadding = MediaQuery.of(context).padding.bottom;
    final barHeight = 64.0;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          height: barHeight + bottomPadding,
          child: Stack(
            clipBehavior: Clip.none,
            alignment: Alignment.topCenter,
            children: [
              // ── Notched bar background ───────────────────────────
              Positioned(
                left: 0,
                right: 0,
                top: 28, // Space for FAB above
                bottom: 0,
                child: ClipPath(
                  clipper: BottomBarClipper(notchRadius: 30),
                  child: Container(
                    decoration: BoxDecoration(
                      color: isDark ? AppColors.darkSurface : AppColors.surface,
                      boxShadow: [
                        BoxShadow(
                          color: isDark
                              ? Colors.black.withValues(alpha: 0.3)
                              : AppColors.primary.withValues(alpha: 0.08),
                          offset: const Offset(0, -4),
                          blurRadius: 16,
                          spreadRadius: 0,
                        ),
                      ],
                    ),
                  ),
                ),
              ),

              // ── Navigation items row ─────────────────────────────
              Positioned(
                left: 0,
                right: 0,
                top: 28,
                bottom: bottomPadding,
                child: Row(
                  children: [
                    // Left items (indices 0, 1)
                    for (int i = 0; i < 2; i++)
                      Expanded(child: _buildNavItem(i, theme, isDark)),

                    // Center space for FAB
                    const SizedBox(width: 64),

                    // Right items (indices 2, 3, 4)
                    for (int i = 2; i < items.length; i++)
                      Expanded(child: _buildNavItem(i, theme, isDark)),
                  ],
                ),
              ),

              // ── Center FAB ───────────────────────────────────────
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: Center(
                  child: CenterFabButton(onTap: onFabTap),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildNavItem(int index, ThemeData theme, bool isDark) {
    final item = items[index];
    final isSelected = index == selectedIndex;

    return InkWell(
      onTap: () => onTap(index),
      customBorder: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // ── Icon ──────────────────────────────────────────────
          AnimatedSwitcher(
            duration: DesignSystem.animFast,
            child: Icon(
              isSelected ? item.activeIcon : item.icon,
              key: ValueKey(isSelected),
              color: isSelected
                  ? AppColors.primary
                  : (isDark ? AppColors.darkTextSecondary : AppColors.textHint),
              size: 24,
            ),
          ),
          const SizedBox(height: 4),

          // ── Label ─────────────────────────────────────────────
          AnimatedDefaultTextStyle(
            duration: DesignSystem.animFast,
            style: theme.textTheme.labelSmall!.copyWith(
              color: isSelected
                  ? AppColors.primary
                  : (isDark ? AppColors.darkTextSecondary : AppColors.textHint),
              fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
            ),
            child: Text(item.label),
          ),

          // ── Active indicator dot ──────────────────────────────
          const SizedBox(height: 2),
          AnimatedContainer(
            duration: DesignSystem.animFast,
            width: isSelected ? 20 : 0,
            height: 3,
            decoration: BoxDecoration(
              color: isSelected ? AppColors.primary : Colors.transparent,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
        ],
      ),
    );
  }
}

/// Center floating action button that sits in the notch of the bottom bar.
class CenterFabButton extends StatelessWidget {
  const CenterFabButton({
    super.key,
    required this.onTap,
  });

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 56,
        height: 56,
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [AppColors.primaryGradientStart, AppColors.primaryGradientEnd],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: AppColors.primary.withValues(alpha: 0.4),
              offset: const Offset(0, 8),
              blurRadius: 16,
            ),
          ],
        ),
        child: const Icon(
          PhosphorIconsFill.plus,
          color: Colors.white,
          size: 28,
        ),
      ),
    );
  }
}

/// Data model for a bottom navigation bar item.
class CustomBottomBarItem {
  const CustomBottomBarItem({
    required this.icon,
    required this.activeIcon,
    required this.label,
  });

  final IconData icon;
  final IconData activeIcon;
  final String label;
}

/// Custom clipper for the bottom bar with a notch for the FAB.
/// Creates a smooth semicircular cutout at the top center.
class BottomBarClipper extends CustomClipper<Path> {
  BottomBarClipper({this.notchRadius = 28.0});

  final double notchRadius;

  @override
  Path getClip(Size size) {
    final path = Path();
    final v = notchRadius * 2;

    // Start from top-left, going right
    path.moveTo(0, notchRadius);

    // Top-left corner radius
    path.arcTo(
      Rect.fromLTWH(0, 0, notchRadius, notchRadius),
      degreeToRadians(180),
      degreeToRadians(90),
      false,
    );

    // Line to left side of notch
    final notchLeft = (size.width / 2) - v / 2 - notchRadius * 0.8;
    path.lineTo(notchLeft, 0);

    // Left curve into notch
    path.arcTo(
      Rect.fromLTWH(notchLeft, 0, notchRadius, notchRadius),
      degreeToRadians(270),
      degreeToRadians(70),
      false,
    );

    // Semicircular notch cutout
    path.arcTo(
      Rect.fromLTWH((size.width / 2) - v / 2, -v / 2, v, v),
      degreeToRadians(160),
      degreeToRadians(-140),
      false,
    );

    // Right curve out of notch
    final notchRight = (size.width / 2) + v / 2 - notchRadius * 0.2;
    path.arcTo(
      Rect.fromLTWH(notchRight, 0, notchRadius, notchRadius),
      degreeToRadians(200),
      degreeToRadians(70),
      false,
    );

    // Line to right side
    path.lineTo(size.width - notchRadius, 0);

    // Top-right corner radius
    path.arcTo(
      Rect.fromLTWH(size.width - notchRadius, 0, notchRadius, notchRadius),
      degreeToRadians(270),
      degreeToRadians(90),
      false,
    );

    // Down to bottom-right
    path.lineTo(size.width, size.height);

    // Bottom edge
    path.lineTo(0, size.height);

    path.close();
    return path;
  }

  @override
  bool shouldReclip(BottomBarClipper oldClipper) => true;

  double degreeToRadians(double degree) {
    return (math.pi / 180) * degree;
  }
}
