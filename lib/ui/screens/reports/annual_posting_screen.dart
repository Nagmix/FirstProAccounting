import 'package:flutter/material.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/currency_formatter.dart';
import '../../../core/utils/money_helper.dart';
import '../../../data/datasources/database_helper.dart';

class AnnualPostingScreen extends StatefulWidget {
  const AnnualPostingScreen({super.key});

  @override
  State<AnnualPostingScreen> createState() => _AnnualPostingScreenState();
}

class _AnnualPostingScreenState extends State<AnnualPostingScreen> {
  bool _isLoading = true;
  List<Map<String, dynamic>> _fiscalYears = [];
  Map<String, double> _currentYearPL = {};
  bool _isPosting = false;
  int _activeYear = DateTime.now().year;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    final db = DatabaseHelper();
    final years = await db.getFiscalYears();

    // Determine the active fiscal year: prefer the most recent open fiscal year
    int activeYear = DateTime.now().year;
    if (years.isNotEmpty) {
      // Find the most recent open fiscal year
      final openYears = years.where((fy) => fy['status'] != 'closed');
      if (openYears.isNotEmpty) {
        activeYear = (openYears.first['year'] as num).toInt();
      } else {
        // All closed – use the most recent fiscal year
        activeYear = (years.first['year'] as num).toInt();
      }
    }

    final pl = await db.getYearProfitLoss(activeYear);

    if (mounted) {
      setState(() {
        _fiscalYears = years;
        _activeYear = activeYear;
        _currentYearPL = pl;
        _isLoading = false;
      });
    }
  }

  Future<void> _performAnnualPosting(int year) async {
    final confirmed = await _showConfirmationDialog(year);
    if (!confirmed) return;

    setState(() => _isPosting = true);

    try {
      final db = DatabaseHelper();
      await db.performAnnualPosting(year);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('تم ترحيل السنة $year بنجاح'), backgroundColor: AppColors.success),
        );
        _loadData();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('حدث خطأ أثناء الترحيل'), backgroundColor: AppColors.error),
        );
      }
    } finally {
      if (mounted) setState(() => _isPosting = false);
    }
  }

  Future<bool> _showConfirmationDialog(int year) async {
    final theme = Theme.of(context);
    final confirmController = TextEditingController();

    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          title: Row(
            children: [
              Icon(Icons.warning_amber_rounded, color: AppColors.warning, size: 28),
              const SizedBox(width: 8),
              Text('تأكيد الترحيل السنوي'),
            ],
          ),
          content: SizedBox(
            width: double.maxFinite,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppColors.warning.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: AppColors.warning.withOpacity(0.3)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('تحذير: هذا الإجراء لا يمكن التراجع عنه!', style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w700, color: AppColors.warning)),
                      const SizedBox(height: 8),
                      Text('سيتم إقفال السنة المالية $year:', style: theme.textTheme.bodySmall),
                      const SizedBox(height: 4),
                      Text('• نقل صافي الربح/الخسارة إلى الأرباح المحتجزة', style: theme.textTheme.bodySmall),
                      Text('• تصفير أرصدة حسابات الإيرادات والتكاليف والمصاريف', style: theme.textTheme.bodySmall),
                      Text('• قفل السنة المالية لمنع أي تعديلات', style: theme.textTheme.bodySmall),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                Text('ملخص الأرباح والخسائر للسنة $year:', style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w700)),
                const SizedBox(height: 8),
                _buildPLRow(theme, 'إجمالي الإيرادات', _currentYearPL['revenue'] ?? 0.0, AppColors.success),
                _buildPLRow(theme, 'إجمالي التكاليف', _currentYearPL['costs'] ?? 0.0, AppColors.error),
                _buildPLRow(theme, 'إجمالي المصاريف', _currentYearPL['expenses'] ?? 0.0, AppColors.warning),
                const Divider(),
                _buildPLRow(theme, 'صافي الربح/الخسارة', _currentYearPL['netProfit'] ?? 0.0, (_currentYearPL['netProfit'] ?? 0.0) >= 0 ? AppColors.success : AppColors.error),
                const SizedBox(height: 16),
                Text('اكتب "تأكيد" للمتابعة:', style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
                const SizedBox(height: 8),
                TextField(
                  controller: confirmController,
                  decoration: InputDecoration(
                    hintText: 'تأكيد',
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('إلغاء'),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: AppColors.error),
              onPressed: () {
                if (confirmController.text.trim() == 'تأكيد') {
                  Navigator.pop(ctx, true);
                } else {
                  ScaffoldMessenger.of(ctx).showSnackBar(
                    const SnackBar(content: Text('يرجى كتابة "تأكيد" للمتابعة'), backgroundColor: AppColors.error),
                  );
                }
              },
              child: const Text('ترحيل', style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
      ),
    );

    confirmController.dispose();
    return result ?? false;
  }

  Widget _buildPLRow(ThemeData theme, String label, double value, Color color) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: theme.textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w500)),
          Text(CurrencyFormatter.formatWithSymbol(value), style: theme.textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w700, color: color)),
        ],
      ),
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
          actions: [
            IconButton(
              icon: const Icon(Icons.refresh),
              tooltip: 'تحديث',
              onPressed: () {
                setState(() => _isLoading = true);
                _loadData();
              },
            ),
          ],
        ),
        body: _isLoading || _isPosting
            ? Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const CircularProgressIndicator(),
                    const SizedBox(height: 16),
                    Text(_isPosting ? 'جارٍ الترحيل...' : 'جارٍ التحميل...', style: theme.textTheme.bodyMedium),
                  ],
                ),
              )
            : SingleChildScrollView(
                padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewPadding.bottom + 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildCurrentYearSection(theme, isDark, _activeYear),
                    const SizedBox(height: 16),
                    _buildFiscalYearsHistory(theme, isDark),
                  ],
                ),
              ),
      ),
    );
  }

  Widget _buildCurrentYearSection(ThemeData theme, bool isDark, int currentYear) {
    final isClosed = _fiscalYears.any((fy) => fy['year'] == currentYear && fy['status'] == 'closed');
    final netProfit = _currentYearPL['netProfit'] ?? 0.0;

    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            netProfit >= 0 ? AppColors.success.withOpacity(0.08) : AppColors.error.withOpacity(0.08),
            netProfit >= 0 ? AppColors.success.withOpacity(0.03) : AppColors.error.withOpacity(0.03),
          ],
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: (netProfit >= 0 ? AppColors.success : AppColors.error).withOpacity(0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.calendar_today, color: AppColors.primary, size: 22),
              const SizedBox(width: 8),
              Text('السنة المالية $currentYear', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
              const Spacer(),
              if (isClosed)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  decoration: BoxDecoration(color: AppColors.error.withOpacity(0.1), borderRadius: BorderRadius.circular(20)),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.lock, size: 14, color: AppColors.error),
                      const SizedBox(width: 4),
                      Text('مقفلة', style: theme.textTheme.labelSmall?.copyWith(color: AppColors.error, fontWeight: FontWeight.w700)),
                    ],
                  ),
                )
              else
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  decoration: BoxDecoration(color: AppColors.success.withOpacity(0.1), borderRadius: BorderRadius.circular(20)),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.lock_open, size: 14, color: AppColors.success),
                      const SizedBox(width: 4),
                      Text('مفتوحة', style: theme.textTheme.labelSmall?.copyWith(color: AppColors.success, fontWeight: FontWeight.w700)),
                    ],
                  ),
                ),
            ],
          ),
          const SizedBox(height: 20),

          // P&L Breakdown
          _buildPLCard(theme, isDark, 'إجمالي الإيرادات', _currentYearPL['revenue'] ?? 0.0, AppColors.success, Icons.trending_up),
          const SizedBox(height: 8),
          _buildPLCard(theme, isDark, 'إجمالي التكاليف', _currentYearPL['costs'] ?? 0.0, AppColors.error, Icons.south_east),
          const SizedBox(height: 8),
          _buildPLCard(theme, isDark, 'إجمالي المصاريف', _currentYearPL['expenses'] ?? 0.0, AppColors.warning, Icons.remove_circle_outline),
          const SizedBox(height: 16),

          // Net profit
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: (netProfit >= 0 ? AppColors.success : AppColors.error).withOpacity(0.1),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: (netProfit >= 0 ? AppColors.success : AppColors.error).withOpacity(0.3)),
            ),
            child: Column(
              children: [
                Icon(netProfit >= 0 ? Icons.trending_up : Icons.trending_down, size: 32, color: netProfit >= 0 ? AppColors.success : AppColors.error),
                const SizedBox(height: 8),
                Text(netProfit >= 0 ? 'صافي الربح' : 'صافي الخسارة', style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
                const SizedBox(height: 4),
                Text(
                  CurrencyFormatter.formatWithSymbol(netProfit.abs()),
                  style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w900, color: netProfit >= 0 ? AppColors.success : AppColors.error),
                ),
              ],
            ),
          ),

          if (!isClosed) ...[
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: () => _performAnnualPosting(currentYear),
                icon: const Icon(Icons.publish, color: Colors.white),
                label: const Text('ترحيل سنوي', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 16)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildPLCard(ThemeData theme, bool isDark, String title, double value, Color color, IconData icon) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withOpacity(0.06),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withOpacity(0.15)),
      ),
      child: Row(
        children: [
          Container(
            width: 36, height: 36,
            decoration: BoxDecoration(color: color.withOpacity(0.15), borderRadius: BorderRadius.circular(10)),
            child: Icon(icon, color: color, size: 18),
          ),
          const SizedBox(width: 12),
          Expanded(child: Text(title, style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600))),
          Text(CurrencyFormatter.formatWithSymbol(value), style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w800, color: color)),
        ],
      ),
    );
  }

  Widget _buildFiscalYearsHistory(ThemeData theme, bool isDark) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkSurface : AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: isDark ? AppColors.darkBorder : AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.history, color: AppColors.primary, size: 20),
              const SizedBox(width: 8),
              Text('سجل السنوات المالية', style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700, color: AppColors.primary)),
            ],
          ),
          const SizedBox(height: 12),
          if (_fiscalYears.isEmpty)
            Padding(
              padding: const EdgeInsets.all(24),
              child: Center(
                child: Column(
                  children: [
                    Icon(Icons.calendar_today, size: 48, color: AppColors.textHint.withOpacity(0.5)),
                    const SizedBox(height: 8),
                    Text('لا توجد سنوات مالية مسجلة', style: theme.textTheme.bodyMedium?.copyWith(color: AppColors.textHint)),
                  ],
                ),
              ),
            )
          else
            ..._fiscalYears.map((fy) {
              final year = (fy['year'] as num).toInt();
              final status = fy['status'] as String? ?? 'open';
              final netProfit = MoneyHelper.readMoney(fy['net_profit']);
              final closedAt = fy['closed_at'] as String?;
              final isClosed = status == 'closed';

              return Card(
                margin: const EdgeInsets.only(bottom: 8),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    children: [
                      Container(
                        width: 44, height: 44,
                        decoration: BoxDecoration(
                          color: (isClosed ? AppColors.error : AppColors.success).withOpacity(0.1),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Icon(isClosed ? Icons.lock : Icons.lock_open, color: isClosed ? AppColors.error : AppColors.success, size: 22),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Text('سنة $year', style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w700)),
                                const SizedBox(width: 8),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: (isClosed ? AppColors.error : AppColors.success).withOpacity(0.1),
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Text(
                                    isClosed ? 'مقفلة' : 'مفتوحة',
                                    style: theme.textTheme.labelSmall?.copyWith(
                                      color: isClosed ? AppColors.error : AppColors.success,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            if (isClosed && closedAt != null) ...[
                              const SizedBox(height: 2),
                              Text('تاريخ الإقفال: ${closedAt.length >= 10 ? closedAt.substring(0, 10) : closedAt}', style: theme.textTheme.bodySmall?.copyWith(color: AppColors.textHint)),
                            ],
                            if (isClosed) ...[
                              const SizedBox(height: 2),
                              Text(
                                'صافي الربح: ${CurrencyFormatter.formatWithSymbol(netProfit)}',
                                style: theme.textTheme.bodySmall?.copyWith(
                                  fontWeight: FontWeight.w600,
                                  color: netProfit >= 0 ? AppColors.success : AppColors.error,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }),
        ],
      ),
    );
  }
}
