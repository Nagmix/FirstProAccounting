import 'package:flutter/material.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/currency_formatter.dart';
import '../../../core/utils/money_helper.dart';
import '../../../core/di/service_locator.dart';
import '../../../data/datasources/repositories/account_repository.dart';
import '../../../data/datasources/repositories/reference_data_repository.dart';

class FiscalYearScreen extends StatefulWidget {
  const FiscalYearScreen({super.key});

  @override
  State<FiscalYearScreen> createState() => _FiscalYearScreenState();
}

class _FiscalYearScreenState extends State<FiscalYearScreen> {
  List<Map<String, dynamic>> _fiscalYears = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadFiscalYears();
  }

  Future<void> _loadFiscalYears() async {
    setState(() => _isLoading = true);
    try {
      _fiscalYears = await locator<AccountRepository>().getFiscalYears();
    } catch (e) {
      debugPrint('Error loading fiscal years: $e');
      _fiscalYears = [];
    }
    if (mounted) setState(() => _isLoading = false);
  }

  Future<void> _closeFiscalYear(int year) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          title: Row(
            children: [
              Icon(Icons.warning_amber_rounded, color: AppColors.warning),
              const SizedBox(width: 8),
              const Text('إقفال السنة المالية'),
            ],
          ),
          content: Text(
            'سيتم إقفال سنة $year المالية.\n\n'
            'يتم إقفال جميع حسابات الإيرادات والمصاريف والتكاليف وتحويل أرصدتها إلى الأرباح المحتجزة.\n\n'
            'هذا الإجراء لا يمكن التراجع عنه. هل أنت متأكد؟',
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('إلغاء')),
            TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: TextButton.styleFrom(foregroundColor: AppColors.error),
              child: const Text('إقفال'),
            ),
          ],
        ),
      ),
    );
    if (confirmed == true) {
      try {
        await locator<AccountRepository>().performAnnualPosting(year);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
                content: Text('تم إقفال السنة المالية بنجاح'),
                backgroundColor: AppColors.success),
          );
        }
        _loadFiscalYears();
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
                content: Text('حدث خطأ أثناء الإقفال'),
                backgroundColor: AppColors.error),
          );
        }
      }
    }
  }

  Future<void> _showCreateFiscalYearDialog() async {
    final now = DateTime.now();
    int selectedYear = now.year + 1;
    String notes = '';

    await showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return Directionality(
              textDirection: TextDirection.rtl,
              child: AlertDialog(
                title: const Text('إنشاء سنة مالية جديدة'),
                content: SizedBox(
                  width: MediaQuery.of(context).size.width * 0.85,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      DropdownButtonFormField<int>(
                        value: selectedYear,
                        decoration: const InputDecoration(
                          labelText: 'السنة المالية',
                          border: OutlineInputBorder(),
                          prefixIcon: Icon(Icons.calendar_today),
                        ),
                        items: List.generate(10, (i) {
                          final y = now.year + i - 1;
                          return DropdownMenuItem(value: y, child: Text('$y'));
                        }),
                        onChanged: (val) {
                          if (val != null) {
                            setDialogState(() => selectedYear = val);
                          }
                        },
                      ),
                      const SizedBox(height: 12),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: AppColors.info.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                              color: AppColors.info.withValues(alpha: 0.2)),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Icon(Icons.date_range,
                                    size: 18, color: AppColors.info),
                                const SizedBox(width: 6),
                                Text(
                                  'الفترة: $selectedYear-01-01 → $selectedYear-12-31',
                                  style: TextStyle(
                                      fontSize: 13, color: AppColors.info),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        decoration: const InputDecoration(
                          labelText: 'ملاحظات (اختياري)',
                          border: OutlineInputBorder(),
                        ),
                        onChanged: (val) => notes = val,
                      ),
                    ],
                  ),
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(ctx),
                    child: const Text('إلغاء'),
                  ),
                  ElevatedButton(
                    onPressed: () async {
                      // Check if year already exists
                      final existing = _fiscalYears
                          .where((fy) => fy['year'] == selectedYear);
                      if (existing.isNotEmpty) {
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(
                                  'السنة المالية $selectedYear موجودة بالفعل'),
                              backgroundColor: AppColors.error,
                            ),
                          );
                        }
                        return;
                      }

                      final navigator = Navigator.of(ctx);
                      final scaffoldMessenger = ScaffoldMessenger.of(context);
                      try {
                        await locator<ReferenceDataRepository>()
                            .insertFiscalYear({
                          'year': selectedYear,
                          'start_date': '$selectedYear-01-01',
                          'end_date': '$selectedYear-12-31',
                          'status': 'open',
                          'net_profit': 0,
                          'notes': notes.isEmpty
                              ? 'السنة المالية $selectedYear'
                              : notes,
                          'created_at': DateTime.now().toIso8601String(),
                          'updated_at': DateTime.now().toIso8601String(),
                        });

                        if (!mounted) return;
                        navigator.pop();
                        scaffoldMessenger.showSnackBar(
                          const SnackBar(
                              content: Text('تم إنشاء السنة المالية بنجاح'),
                              backgroundColor: AppColors.success),
                        );
                        _loadFiscalYears();
                      } catch (e) {
                        if (!mounted) return;
                        scaffoldMessenger.showSnackBar(
                          SnackBar(
                              content: Text('حدث خطأ أثناء الإنشاء'),
                              backgroundColor: AppColors.error),
                        );
                      }
                    },
                    style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        foregroundColor: Colors.white),
                    child: const Text('إنشاء'),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('السنوات المالية'),
        ),
        body: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : _fiscalYears.isEmpty
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.calendar_today,
                            size: 64, color: AppColors.textHint),
                        const SizedBox(height: 16),
                        Text('لا توجد سنوات مالية',
                            style: theme.textTheme.titleMedium
                                ?.copyWith(color: AppColors.textSecondary)),
                        const SizedBox(height: 8),
                        Text('أنشئ سنة مالية جديدة للبدء',
                            style: theme.textTheme.bodySmall
                                ?.copyWith(color: AppColors.textHint)),
                      ],
                    ),
                  )
                : RefreshIndicator(
                    onRefresh: _loadFiscalYears,
                    child: ListView.builder(
                      padding: const EdgeInsets.all(16),
                      itemCount: _fiscalYears.length,
                      itemBuilder: (context, index) {
                        final fy = _fiscalYears[index];
                        final isOpen = (fy['status'] as String?) == 'open';
                        final year = fy['year'] as int? ?? 0;
                        final netProfit =
                            MoneyHelper.readMoney(fy['net_profit']);
                        final startDate =
                            fy['start_date'] as String? ?? '$year-01-01';
                        final endDate =
                            fy['end_date'] as String? ?? '$year-12-31';
                        final closedAt = fy['closed_at'] as String?;
                        final notes = fy['notes'] as String? ?? '';

                        return Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: Material(
                            color: isDark
                                ? AppColors.darkSurface
                                : AppColors.surface,
                            borderRadius: BorderRadius.circular(14),
                            elevation: 1,
                            shadowColor: isDark
                                ? Colors.black26
                                : AppColors.primary.withValues(alpha: 0.06),
                            child: Container(
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(14),
                                border: isOpen
                                    ? Border.all(
                                        color: AppColors.info
                                            .withValues(alpha: 0.3),
                                        width: 1.5)
                                    : null,
                              ),
                              child: Padding(
                                padding: const EdgeInsets.all(16),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Container(
                                          width: 42,
                                          height: 42,
                                          decoration: BoxDecoration(
                                            color: isOpen
                                                ? AppColors.info
                                                    .withValues(alpha: 0.1)
                                                : AppColors.success
                                                    .withValues(alpha: 0.1),
                                            borderRadius:
                                                BorderRadius.circular(12),
                                          ),
                                          child: Icon(
                                            isOpen
                                                ? Icons.lock_open
                                                : Icons.lock,
                                            color: isOpen
                                                ? AppColors.info
                                                : AppColors.success,
                                            size: 20,
                                          ),
                                        ),
                                        const SizedBox(width: 12),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                'السنة المالية $year',
                                                style: theme
                                                    .textTheme.bodyMedium
                                                    ?.copyWith(
                                                  fontWeight: FontWeight.w600,
                                                  color: isDark
                                                      ? AppColors
                                                          .darkTextPrimary
                                                      : AppColors.textPrimary,
                                                ),
                                              ),
                                              const SizedBox(height: 2),
                                              Text(
                                                '$startDate → $endDate',
                                                style: theme.textTheme.bodySmall
                                                    ?.copyWith(
                                                  color: isDark
                                                      ? AppColors
                                                          .darkTextSecondary
                                                      : AppColors.textSecondary,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                              horizontal: 10, vertical: 4),
                                          decoration: BoxDecoration(
                                            color: isOpen
                                                ? AppColors.info
                                                    .withValues(alpha: 0.1)
                                                : AppColors.success
                                                    .withValues(alpha: 0.1),
                                            borderRadius:
                                                BorderRadius.circular(8),
                                          ),
                                          child: Text(
                                            isOpen ? 'مفتوحة' : 'مقفلة',
                                            style: theme.textTheme.labelSmall
                                                ?.copyWith(
                                              color: isOpen
                                                  ? AppColors.info
                                                  : AppColors.success,
                                              fontWeight: FontWeight.w700,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                    if (!isOpen) ...[
                                      const SizedBox(height: 16),
                                      const Divider(height: 1),
                                      const SizedBox(height: 12),
                                      _buildSummaryRow(
                                        theme,
                                        'صافي الربح/الخسارة',
                                        netProfit,
                                        netProfit >= 0
                                            ? AppColors.success
                                            : AppColors.error,
                                        isBold: true,
                                      ),
                                      if (closedAt != null &&
                                          closedAt.isNotEmpty) ...[
                                        const SizedBox(height: 8),
                                        Row(
                                          children: [
                                            Icon(Icons.access_time,
                                                size: 14,
                                                color: AppColors.textHint),
                                            const SizedBox(width: 4),
                                            Text(
                                              'تاريخ الإقفال: ${closedAt.length >= 10 ? closedAt.substring(0, 10) : closedAt}',
                                              style: theme.textTheme.bodySmall
                                                  ?.copyWith(
                                                      color:
                                                          AppColors.textHint),
                                            ),
                                          ],
                                        ),
                                      ],
                                    ],
                                    if (notes.isNotEmpty && !isOpen) ...[
                                      const SizedBox(height: 8),
                                      Text(
                                        notes,
                                        style: theme.textTheme.bodySmall
                                            ?.copyWith(
                                                color: AppColors.textSecondary),
                                      ),
                                    ],
                                    if (isOpen) ...[
                                      const SizedBox(height: 12),
                                      Row(
                                        mainAxisAlignment:
                                            MainAxisAlignment.end,
                                        children: [
                                          ElevatedButton.icon(
                                            onPressed: () =>
                                                _closeFiscalYear(year),
                                            icon: const Icon(Icons.lock,
                                                size: 18),
                                            label: const Text('إقفال السنة'),
                                            style: ElevatedButton.styleFrom(
                                              backgroundColor: AppColors.error,
                                              foregroundColor: Colors.white,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
        floatingActionButton: FloatingActionButton(
          onPressed: _showCreateFiscalYearDialog,
          backgroundColor: AppColors.primary,
          child: const Icon(Icons.add, color: Colors.white),
        ),
      ),
    );
  }

  Widget _buildSummaryRow(
      ThemeData theme, String label, double value, Color color,
      {bool isBold = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: theme.textTheme.bodySmall?.copyWith(
              color: AppColors.textSecondary,
              fontWeight: isBold ? FontWeight.w700 : FontWeight.normal,
            ),
          ),
          Text(
            CurrencyFormatter.format(value),
            style: theme.textTheme.bodySmall?.copyWith(
              color: color,
              fontWeight: isBold ? FontWeight.w700 : FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
