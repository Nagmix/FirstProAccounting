import 'package:flutter/material.dart';
import 'package:firstpro/core/theme/app_colors.dart';
import 'package:firstpro/core/utils/excel_exporter.dart';

// ═══════════════════════════════════════════════════════════════════
//  Report Export FAB – floating button with popup menu for
//  Excel export and print options.
// ═══════════════════════════════════════════════════════════════════

class ReportExportFab extends StatelessWidget {
  final List<Map<String, dynamic>> reportRows;
  final Map<String, double> reportTotals;
  final String reportName;

  const ReportExportFab({
    super.key,
    required this.reportRows,
    required this.reportTotals,
    required this.reportName,
  });

  Future<void> _exportToExcel(BuildContext context) async {
    if (reportRows.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('لا توجد بيانات للتصدير'),
            backgroundColor: AppColors.warning),
      );
      return;
    }
    try {
      await ExcelExporter.exportGenericReport(
        reportName: reportName,
        rows: reportRows,
        totals: reportTotals,
      );
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('حدث خطأ أثناء التصدير'),
              backgroundColor: AppColors.error),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return PopupMenuButton<String>(
      offset: const Offset(0, -80),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      color: isDark ? AppColors.darkSurface : AppColors.surface,
      onSelected: (value) {
        switch (value) {
          case 'excel':
            _exportToExcel(context);
          case 'print':
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                  content: Text('طباعة – قريباً'),
                  backgroundColor: AppColors.info),
            );
        }
      },
      itemBuilder: (context) => [
        PopupMenuItem(
          value: 'excel',
          child: Row(
            children: [
              Icon(Icons.table_chart, size: 20, color: AppColors.success),
              const SizedBox(width: 8),
              Text('تصدير Excel', style: theme.textTheme.bodyMedium),
            ],
          ),
        ),
        PopupMenuItem(
          value: 'print',
          child: Row(
            children: [
              Icon(Icons.print, size: 20, color: AppColors.primary),
              const SizedBox(width: 8),
              Text('طباعة', style: theme.textTheme.bodyMedium),
            ],
          ),
        ),
      ],
      child: Container(
        decoration: BoxDecoration(
          gradient: AppColors.primaryGradient,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: AppColors.primary.withValues(alpha: 0.3),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.file_download, color: Colors.white, size: 22),
            SizedBox(width: 8),
            Text('تصدير',
                style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                    fontSize: 14)),
            SizedBox(width: 4),
            Icon(Icons.arrow_drop_up, color: Colors.white, size: 18),
          ],
        ),
      ),
    );
  }
}
