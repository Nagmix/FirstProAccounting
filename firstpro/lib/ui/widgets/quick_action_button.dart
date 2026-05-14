import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';

/// A reusable quick-action button displayed in the dashboard grid.
///
/// Shows an [icon] above a [label] inside a Material 3 Card with
/// an InkWell ripple effect.
class QuickActionButton extends StatelessWidget {
  const QuickActionButton({
    super.key,
    required this.label,
    required this.icon,
    required this.onTap,
    this.color,
  });

  final String label;
  final IconData icon;
  final VoidCallback onTap;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final effectiveColor = color ?? AppColors.primary;

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 6, vertical: 5),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // ── Icon circle ───────────────────────────────────
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  color: effectiveColor.withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  icon,
                  color: effectiveColor,
                  size: 22,
                ),
              ),
              const SizedBox(height: 10),

              // ── Label ─────────────────────────────────────────
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
    );
  }
}
