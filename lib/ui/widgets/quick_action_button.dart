import 'package:flutter/material.dart';

import 'package:firstpro/core/theme/app_colors.dart';
import 'package:firstpro/core/theme/design_system.dart';

/// A modern quick-action button displayed in the dashboard grid.
/// Shows an [icon] above a [label] inside a card with gradient
/// icon background and smooth InkWell ripple effect.
///
/// When [isLarge] is true, the button renders in a larger format
/// suitable for "Quick Operations" (POS, sale invoice, etc.) with
/// bigger icon container, larger text, and a colored accent bar.
class QuickActionButton extends StatelessWidget {
  const QuickActionButton({
    super.key,
    required this.label,
    required this.icon,
    required this.onTap,
    this.color,
    this.isLarge = false,
  });

  final String label;
  final IconData icon;
  final VoidCallback onTap;
  final Color? color;
  final bool isLarge;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final effectiveColor = color ?? AppColors.primary;

    if (isLarge) {
      return _buildLargeButton(context, theme, isDark, effectiveColor);
    }
    return _buildNormalButton(context, theme, isDark, effectiveColor);
  }

  Widget _buildNormalButton(
    BuildContext context,
    ThemeData theme,
    bool isDark,
    Color effectiveColor,
  ) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkSurface : AppColors.surface,
        borderRadius: DesignSystem.borderRadius16,
        boxShadow: DesignSystem.cardShadow(isLight: !isDark),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: DesignSystem.borderRadius16,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // ── Icon with gradient background ───────────────────
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        effectiveColor.withValues(alpha: 0.18),
                        effectiveColor.withValues(alpha: 0.06),
                      ],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Icon(
                    icon,
                    color: effectiveColor,
                    size: 22,
                  ),
                ),
                const SizedBox(height: 10),

                // ── Label ───────────────────────────────────────────
                Text(
                  label,
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: isDark
                        ? AppColors.darkTextPrimary
                        : AppColors.textPrimary,
                    height: 1.3,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildLargeButton(
    BuildContext context,
    ThemeData theme,
    bool isDark,
    Color effectiveColor,
  ) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 5, vertical: 5),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            effectiveColor.withValues(alpha: 0.10),
            isDark ? AppColors.darkSurface : AppColors.surface,
          ],
          begin: Alignment.topRight,
          end: Alignment.bottomLeft,
        ),
        borderRadius: DesignSystem.borderRadius16,
        boxShadow: DesignSystem.cardShadow(isLight: !isDark),
        border: Border.all(
          color: effectiveColor.withValues(alpha: 0.12),
          width: 0.5,
        ),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: DesignSystem.borderRadius16,
          child: ClipRRect(
            borderRadius: DesignSystem.borderRadius16,
            child: Stack(
              children: [
                // ── Colored accent bar on the right (RTL) ─────────
                Positioned(
                  right: 0,
                  top: 0,
                  bottom: 0,
                  child: Container(
                    width: 4,
                    decoration: BoxDecoration(
                      color: effectiveColor.withValues(alpha: 0.5),
                      borderRadius: const BorderRadius.only(
                        topLeft: Radius.circular(4),
                        bottomLeft: Radius.circular(4),
                      ),
                    ),
                  ),
                ),

                // ── Content ────────────────────────────────────────
                Padding(
                  padding: const EdgeInsets.symmetric(
                    vertical: 18,
                    horizontal: 14,
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      // ── Large icon with gradient circle ─────────
                      Container(
                        width: 56,
                        height: 56,
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [
                              effectiveColor.withValues(alpha: 0.22),
                              effectiveColor.withValues(alpha: 0.06),
                            ],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: effectiveColor.withValues(alpha: 0.15),
                              offset: const Offset(0, 4),
                              blurRadius: 10,
                            ),
                          ],
                        ),
                        child: Icon(
                          icon,
                          color: effectiveColor,
                          size: 26,
                        ),
                      ),
                      const SizedBox(height: 12),

                      // ── Label (larger & bolder) ─────────────────
                      Text(
                        label,
                        textAlign: TextAlign.center,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                          color: isDark
                              ? AppColors.darkTextPrimary
                              : AppColors.textPrimary,
                          height: 1.3,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
