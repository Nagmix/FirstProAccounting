import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/design_system.dart';
import '../../core/utils/currency_formatter.dart';

/// A modern statistics card with accent bar, gradient icon background,
/// and smooth entry animation. Inspired by the fitness app UI design.
class StatCard extends StatelessWidget {
  const StatCard({
    super.key,
    required this.title,
    required this.value,
    required this.icon,
    required this.color,
    this.trendPercentage,
    this.trendIsUp = true,
    this.subtitle,
    this.isCount = false,
    this.accentBarColor,
  });

  final String title;
  final double value;
  final IconData icon;
  final Color color;
  final double? trendPercentage;
  final bool trendIsUp;
  final String? subtitle;
  final bool isCount;
  final Color? accentBarColor;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final effectiveAccentColor = accentBarColor ?? color;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 6, vertical: 5),
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkSurface : AppColors.surface,
        borderRadius: DesignSystem.borderRadius16,
        boxShadow: DesignSystem.cardShadow(isLight: !isDark),
      ),
      child: ClipRRect(
        borderRadius: DesignSystem.borderRadius16,
        child: Stack(
          children: [
            // ── Accent bar on the right side (RTL) ────────────────
            Positioned(
              right: 0,
              top: 0,
              bottom: 0,
              child: Container(
                width: 4,
                decoration: BoxDecoration(
                  color: effectiveAccentColor.withOpacity(0.6),
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(4),
                    bottomLeft: Radius.circular(4),
                  ),
                ),
              ),
            ),

            // ── Card content ──────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 12, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // ── Icon + Trend row ────────────────────────────
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      // Gradient icon container
                      Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [
                              color.withOpacity(0.15),
                              color.withOpacity(0.05),
                            ],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Icon(icon, color: color, size: 22),
                      ),

                      // Trend indicator
                      if (trendPercentage != null) _buildTrend(isDark),
                    ],
                  ),
                  const Spacer(),

                  // ── Value ───────────────────────────────────────
                  Text(
                    isCount
                        ? value.toInt().toString()
                        : CurrencyFormatter.formatCompactWithSymbol(value),
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w800,
                      color: isDark ? AppColors.darkTextPrimary : AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 4),

                  // ── Title ───────────────────────────────────────
                  Text(
                    title,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: isDark ? AppColors.darkTextSecondary : AppColors.textSecondary,
                      fontWeight: FontWeight.w500,
                    ),
                  ),

                  // ── Optional subtitle with progress bar ─────────
                  if (subtitle != null) ...[
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Text(
                          subtitle!,
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: isDark ? AppColors.darkTextSecondary : AppColors.textHint,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: DesignSystem.progressBar(
                            progress: 0.6, // Placeholder
                            color: color,
                            width: double.infinity,
                            height: 3,
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTrend(bool isDark) {
    final isPositive = trendIsUp;
    final trendColor = isPositive ? AppColors.success : AppColors.error;
    final arrowIcon = isPositive ? Icons.trending_up : Icons.trending_down;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: trendColor.withOpacity(0.1),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(arrowIcon, size: 14, color: trendColor),
          const SizedBox(width: 2),
          Text(
            '${trendPercentage!.toStringAsFixed(1)}%',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: trendColor,
            ),
          ),
        ],
      ),
    );
  }
}
