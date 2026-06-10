import 'package:flutter/material.dart';
import 'package:firstpro/core/theme/app_colors.dart';
import 'package:firstpro/ui/screens/reports/widgets/report_helpers.dart';

// ═══════════════════════════════════════════════════════════════════
//  Report Cards Grid – displays a grid of selectable report cards
//  for a given ReportGroup.
// ═══════════════════════════════════════════════════════════════════

class ReportCardsGrid extends StatelessWidget {
  final ReportGroup group;
  final String? selectedReportKey;
  final ValueChanged<ReportItem> onReportSelected;

  const ReportCardsGrid({
    super.key,
    required this.group,
    required this.selectedReportKey,
    required this.onReportSelected,
  });

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        childAspectRatio: 2.2,
        crossAxisSpacing: 8,
        mainAxisSpacing: 8,
      ),
      itemCount: group.items.length,
      itemBuilder: (context, index) {
        final item = group.items[index];
        final isSelected = selectedReportKey == item.key;
        return _ReportCard(
          item: item,
          isSelected: isSelected,
          isDark: Theme.of(context).brightness == Brightness.dark,
          onTap: () => onReportSelected(item),
        );
      },
    );
  }
}

// ── Individual Report Card ─────────────────────────────────────

class _ReportCard extends StatelessWidget {
  final ReportItem item;
  final bool isSelected;
  final bool isDark;
  final VoidCallback onTap;

  const _ReportCard({
    required this.item,
    required this.isSelected,
    required this.isDark,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bgColor = isSelected
        ? item.color.withValues(alpha: isDark ? 0.25 : 0.1)
        : (isDark ? AppColors.darkSurfaceVariant : AppColors.surfaceVariant);
    final borderColor = isSelected
        ? item.color
        : (isDark ? AppColors.darkBorder : AppColors.border);
    final iconColor = isSelected
        ? item.color
        : (isDark ? AppColors.darkTextSecondary : AppColors.textSecondary);

    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: borderColor, width: isSelected ? 2 : 1),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                      color: item.color.withValues(alpha: 0.15),
                      blurRadius: 8,
                      offset: const Offset(0, 2))
                ]
              : null,
        ),
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Row(
              children: [
                Icon(item.icon, size: 28, color: iconColor),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    item.name,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight:
                          isSelected ? FontWeight.w800 : FontWeight.w600,
                      color: isSelected
                          ? item.color
                          : (isDark
                              ? AppColors.darkTextPrimary
                              : AppColors.textPrimary),
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (isSelected)
                  Icon(Icons.check_circle, size: 18, color: item.color),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              getReportDescription(item.key),
              style: theme.textTheme.bodySmall?.copyWith(
                fontSize: 10,
                color: isDark
                    ? AppColors.darkTextTertiary
                    : AppColors.textTertiary,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }
}
