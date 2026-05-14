import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../core/utils/currency_formatter.dart';

/// A reusable statistics card for the dashboard.
///
/// Displays a large numeric [value], a [title], an [icon] inside a
/// coloured circle, and an optional trend indicator (percentage with
/// up/down arrow).
///
/// When [isCount] is `true`, the value is shown as a plain integer
/// without a currency symbol (e.g. "156" instead of "156 ر.س").
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
  });

  final String title;
  final double value;
  final IconData icon;
  final Color color;
  final double? trendPercentage;
  final bool trendIsUp;
  final String? subtitle;

  /// When `true`, display the value as a plain integer without the
  /// currency symbol.  Useful for counts (e.g. number of customers).
  final bool isCount;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Icon + Trend row ────────────────────────────────
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                // Colored circle with icon
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.12),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(icon, color: color, size: 22),
                ),

                // Trend indicator
                if (trendPercentage != null) _buildTrend(isDark),
              ],
            ),
            const SizedBox(height: 14),

            // ── Value ───────────────────────────────────────────
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

            // ── Title ───────────────────────────────────────────
            Text(
              title,
              style: theme.textTheme.bodySmall?.copyWith(
                color: isDark ? AppColors.darkTextSecondary : AppColors.textSecondary,
                fontWeight: FontWeight.w500,
              ),
            ),

            // ── Optional subtitle ───────────────────────────────
            if (subtitle != null) ...[
              const SizedBox(height: 2),
              Text(
                subtitle!,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: isDark ? AppColors.darkTextSecondary : AppColors.textHint,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// Builds the trend arrow + percentage badge.
  Widget _buildTrend(bool isDark) {
    final isPositive = trendIsUp;
    final trendColor = isPositive ? AppColors.success : AppColors.error;
    final arrowIcon = isPositive ? Icons.trending_up : Icons.trending_down;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: trendColor.withValues(alpha: 0.1),
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
