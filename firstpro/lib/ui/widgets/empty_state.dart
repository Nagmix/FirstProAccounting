import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';

/// A reusable empty-state widget displayed when a list has no items.
///
/// Shows a large icon, a title, a subtitle, and an optional action button.
/// Designed for Arabic RTL layouts in the FirstPro accounting app.
class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    this.actionLabel,
    this.onAction,
  });

  /// The large icon displayed at the top of the empty state.
  final IconData icon;

  /// Primary title text (e.g. "لا يوجد عملاء").
  final String title;

  /// Secondary subtitle text providing more context.
  final String subtitle;

  /// Optional label for the action button (e.g. "إضافة عميل").
  final String? actionLabel;

  /// Optional callback invoked when the action button is pressed.
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isLight = theme.brightness == Brightness.light;

    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 48),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // ── Large icon ────────────────────────────────────────
            Container(
              width: 96,
              height: 96,
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.08),
                shape: BoxShape.circle,
              ),
              child: Icon(
                icon,
                size: 48,
                color: AppColors.primary.withValues(alpha: 0.6),
              ),
            ),
            const SizedBox(height: 24),

            // ── Title ─────────────────────────────────────────────
            Text(
              title,
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w700,
                color: isLight ? AppColors.textPrimary : AppColors.darkTextPrimary,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),

            // ── Subtitle ──────────────────────────────────────────
            Text(
              subtitle,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: isLight ? AppColors.textSecondary : AppColors.darkTextSecondary,
                height: 1.5,
              ),
              textAlign: TextAlign.center,
            ),

            // ── Optional action button ────────────────────────────
            if (actionLabel != null && onAction != null) ...[
              const SizedBox(height: 24),
              ElevatedButton.icon(
                onPressed: onAction,
                icon: const Icon(Icons.add, size: 20),
                label: Text(actionLabel!),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
