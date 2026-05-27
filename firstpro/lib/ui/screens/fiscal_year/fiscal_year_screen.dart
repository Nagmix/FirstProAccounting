import 'package:flutter/material.dart';
import '../../../core/theme/app_colors.dart';
import '../../../data/datasources/database_helper.dart';

class FiscalYearScreen extends StatefulWidget {
  const FiscalYearScreen({super.key});

  @override
  State<FiscalYearScreen> createState() => _FiscalYearScreenState();
}

class _FiscalYearScreenState extends State<FiscalYearScreen> {
  final DatabaseHelper _db = DatabaseHelper();
  List<Map<String, dynamic>> _fiscalYears = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadFiscalYears();
  }

  Future<void> _loadFiscalYears() async {
    setState(() => _isLoading = true);
    _fiscalYears = await _db.getAllFiscalYears();
    setState(() => _isLoading = false);
  }

  Future<void> _closeFiscalYear(int id) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('إقفال السنة المالية'),
        content: const Text(
          'سيتم إقفال جميع حسابات الإيرادات والمصاريف والتكاليف وتحويل أرصدتها إلى الأرباح المحتجزة.\n\nهذا الإجراء لا يمكن التراجع عنه. هل أنت متأكد؟',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: AppColors.error),
            child: const Text('إقفال'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      try {
        await _db.closeFiscalYear(id);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('تم إقفال السنة المالية بنجاح'), backgroundColor: AppColors.success),
          );
        }
        _loadFiscalYears();
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('خطأ في الإقفال: $e'), backgroundColor: AppColors.error),
          );
        }
      }
    }
  }

  Future<void> _showCreateFiscalYearDialog() async {
    final nameController = TextEditingController();
    final now = DateTime.now();
    DateTime startDate = DateTime(now.year, 1, 1);
    DateTime endDate = DateTime(now.year, 12, 31);
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
                      TextField(
                        controller: nameController,
                        decoration: const InputDecoration(
                          labelText: 'اسم السنة المالية',
                          border: OutlineInputBorder(),
                          hintText: 'مثال: السنة المالية 2025',
                        ),
                      ),
                      const SizedBox(height: 12),
                      InkWell(
                        onTap: () async {
                          final picked = await showDatePicker(
                            context: context,
                            initialDate: startDate,
                            firstDate: DateTime(2020),
                            lastDate: DateTime(2040),
                          );
                          if (picked != null) setDialogState(() => startDate = picked);
                        },
                        child: InputDecorator(
                          decoration: const InputDecoration(
                            labelText: 'تاريخ البداية',
                            border: OutlineInputBorder(),
                          ),
                          child: Text('${startDate.year}-${startDate.month.toString().padLeft(2, '0')}-${startDate.day.toString().padLeft(2, '0')}'),
                        ),
                      ),
                      const SizedBox(height: 12),
                      InkWell(
                        onTap: () async {
                          final picked = await showDatePicker(
                            context: context,
                            initialDate: endDate,
                            firstDate: DateTime(2020),
                            lastDate: DateTime(2040),
                          );
                          if (picked != null) setDialogState(() => endDate = picked);
                        },
                        child: InputDecorator(
                          decoration: const InputDecoration(
                            labelText: 'تاريخ النهاية',
                            border: OutlineInputBorder(),
                          ),
                          child: Text('${endDate.year}-${endDate.month.toString().padLeft(2, '0')}-${endDate.day.toString().padLeft(2, '0')}'),
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        decoration: const InputDecoration(
                          labelText: 'ملاحظات',
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
                      if (nameController.text.isEmpty) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('يرجى إدخال اسم السنة المالية'), backgroundColor: AppColors.error),
                        );
                        return;
                      }

                      // Validate no overlap with existing fiscal years
                      final newStart = startDate;
                      final newEnd = endDate;
                      for (final existing in _fiscalYears) {
                        final existStartStr = existing['start_date'] as String? ?? '';
                        final existEndStr = existing['end_date'] as String? ?? '';
                        DateTime? existStart, existEnd;
                        try { existStart = DateTime.parse(existStartStr); } catch (_) {}
                        try { existEnd = DateTime.parse(existEndStr); } catch (_) {}
                        if (existStart == null || existEnd == null) continue;

                        // Check overlap: two ranges overlap if start1 <= end2 AND start2 <= end1
                        final overlaps = !newStart.isAfter(existEnd) && !existStart.isAfter(newEnd);
                        if (overlaps) {
                          if (mounted) {
                            await showDialog(
                              context: context,
                              builder: (dCtx) => Directionality(
                                textDirection: TextDirection.rtl,
                                child: AlertDialog(
                                  title: Row(
                                    children: [
                                      Icon(Icons.warning_amber_rounded, color: AppColors.warning),
                                      const SizedBox(width: 8),
                                      Text('تداخل في التواريخ'),
                                    ],
                                  ),
                                  content: Text(
                                    'الفترة المحددة (${newStart.year}-${newStart.month.toString().padLeft(2, '0')}-${newStart.day.toString().padLeft(2, '0')} → ${newEnd.year}-${newEnd.month.toString().padLeft(2, '0')}-${newEnd.day.toString().padLeft(2, '0')}) تتداخل مع السنة المالية "${existing['name'] ?? ''}" (${existStartStr} → ${existEndStr}).\n\nيرجى اختيار فترة لا تتداخل مع السنوات المالية الموجودة.',
                                  ),
                                  actions: [
                                    TextButton(
                                      onPressed: () => Navigator.pop(dCtx),
                                      child: const Text('حسناً'),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          }
                          return;
                        }
                      }

                      final now = DateTime.now().toIso8601String();
                      await _db.insertFiscalYear({
                        'name': nameController.text,
                        'start_date': '${startDate.year}-${startDate.month.toString().padLeft(2, '0')}-${startDate.day.toString().padLeft(2, '0')}',
                        'end_date': '${endDate.year}-${endDate.month.toString().padLeft(2, '0')}-${endDate.day.toString().padLeft(2, '0')}',
                        'status': 'open',
                        'notes': notes,
                        'created_at': now,
                        'updated_at': now,
                      });

                      if (mounted) {
                        Navigator.pop(ctx);
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('تم إنشاء السنة المالية بنجاح'), backgroundColor: AppColors.success),
                        );
                      }
                      _loadFiscalYears();
                    },
                    style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary, foregroundColor: Colors.white),
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
          title: const Text('الترحيل السنوي'),
        ),
        body: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : _fiscalYears.isEmpty
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.calendar_today, size: 64, color: AppColors.textHint),
                        const SizedBox(height: 16),
                        Text('لا توجد سنوات مالية', style: theme.textTheme.titleMedium?.copyWith(color: AppColors.textSecondary)),
                        const SizedBox(height: 8),
                        Text('أنشئ سنة مالية جديدة للبدء', style: theme.textTheme.bodySmall?.copyWith(color: AppColors.textHint)),
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
                        final totalRevenue = (fy['total_revenue'] as num?)?.toDouble() ?? 0.0;
                        final totalExpenses = (fy['total_expenses'] as num?)?.toDouble() ?? 0.0;
                        final totalCosts = (fy['total_costs'] as num?)?.toDouble() ?? 0.0;
                        final netProfit = (fy['net_profit'] as num?)?.toDouble() ?? 0.0;

                        return Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: Material(
                            color: isDark ? AppColors.darkSurface : AppColors.surface,
                            borderRadius: BorderRadius.circular(14),
                            elevation: 1,
                            shadowColor: isDark ? Colors.black26 : AppColors.primary.withValues(alpha: 0.06),
                            child: Container(
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(14),
                                border: isOpen ? Border.all(color: AppColors.info.withValues(alpha: 0.3), width: 1.5) : null,
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
                                            color: isOpen ? AppColors.info.withValues(alpha: 0.1) : AppColors.success.withValues(alpha: 0.1),
                                            borderRadius: BorderRadius.circular(12),
                                          ),
                                          child: Icon(
                                            isOpen ? Icons.lock_open : Icons.lock,
                                            color: isOpen ? AppColors.info : AppColors.success,
                                            size: 20,
                                          ),
                                        ),
                                        const SizedBox(width: 12),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                fy['name'] as String? ?? '',
                                                style: theme.textTheme.bodyMedium?.copyWith(
                                                  fontWeight: FontWeight.w600,
                                                  color: isDark ? AppColors.darkTextPrimary : AppColors.textPrimary,
                                                ),
                                              ),
                                              const SizedBox(height: 2),
                                              Text(
                                                '${fy['start_date'] ?? ''} → ${fy['end_date'] ?? ''}',
                                                style: theme.textTheme.bodySmall?.copyWith(
                                                  color: isDark ? AppColors.darkTextSecondary : AppColors.textSecondary,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                          decoration: BoxDecoration(
                                            color: isOpen ? AppColors.info.withValues(alpha: 0.1) : AppColors.success.withValues(alpha: 0.1),
                                            borderRadius: BorderRadius.circular(8),
                                          ),
                                          child: Text(
                                            isOpen ? 'مفتوحة' : 'مقفلة',
                                            style: theme.textTheme.labelSmall?.copyWith(
                                              color: isOpen ? AppColors.info : AppColors.success,
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
                                      _buildSummaryRow(theme, 'إجمالي الإيرادات', totalRevenue, AppColors.success),
                                      _buildSummaryRow(theme, 'إجمالي التكاليف', totalCosts, AppColors.warning),
                                      _buildSummaryRow(theme, 'إجمالي المصاريف', totalExpenses, AppColors.error),
                                      const Divider(height: 16),
                                      _buildSummaryRow(
                                        theme,
                                        'صافي الربح',
                                        netProfit,
                                        netProfit >= 0 ? AppColors.success : AppColors.error,
                                        isBold: true,
                                      ),
                                    ],
                                    if (isOpen) ...[
                                      const SizedBox(height: 12),
                                      Row(
                                        mainAxisAlignment: MainAxisAlignment.end,
                                        children: [
                                          ElevatedButton.icon(
                                            onPressed: () => _closeFiscalYear(fy['id'] as int),
                                            icon: const Icon(Icons.lock, size: 18),
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

  Widget _buildSummaryRow(ThemeData theme, String label, double value, Color color, {bool isBold = false}) {
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
            value.toStringAsFixed(2),
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
