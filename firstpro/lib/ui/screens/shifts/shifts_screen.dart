import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/utils/currency_formatter.dart';
import '../../../core/utils/date_formatter.dart';
import '../../../data/datasources/database_helper.dart';

/// Shifts management screen – allows opening/closing shifts with balance verification.
///
/// Layout (all RTL):
/// 1. Current shift status card
/// 2. Open new shift form (when no active shift)
/// 3. Shift history list
class ShiftsScreen extends StatefulWidget {
  const ShiftsScreen({super.key});

  @override
  State<ShiftsScreen> createState() => _ShiftsScreenState();
}

class _ShiftsScreenState extends State<ShiftsScreen> {
  bool _isLoading = true;
  Map<String, dynamic>? _activeShift;
  List<Map<String, dynamic>> _shiftHistory = [];
  List<Map<String, dynamic>> _cashBoxes = [];

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    final db = DatabaseHelper();
    final activeShift = await db.getActiveShift();
    final allShifts = await db.getAllShifts();
    final cashBoxes = await db.getAllCashBoxes();

    if (mounted) {
      setState(() {
        _activeShift = activeShift;
        _shiftHistory = allShifts.where((s) => s['status'] == 'closed').toList();
        _cashBoxes = cashBoxes;
        _isLoading = false;
      });
    }
  }

  // ═══════════════════════════════════════════════════════════════════
  //  OPEN SHIFT
  // ═══════════════════════════════════════════════════════════════════
  void _showOpenShiftDialog() {
    final balanceController = TextEditingController();
    int? selectedCashBoxId;

    if (_cashBoxes.isNotEmpty) {
      selectedCashBoxId = _cashBoxes.first['id'] as int?;
    }

    showDialog(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: StatefulBuilder(
          builder: (ctx, setDialogState) => AlertDialog(
            title: const Text('فتح وردية جديدة'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Cash box selector
                if (_cashBoxes.isNotEmpty) ...[
                  DropdownButtonFormField<int>(
                    value: selectedCashBoxId,
                    decoration: InputDecoration(
                      labelText: 'الصندوق',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    items: _cashBoxes.map((cb) => DropdownMenuItem(
                      value: cb['id'] as int?,
                      child: Text(cb['name'] as String),
                    )).toList(),
                    onChanged: (value) {
                      setDialogState(() => selectedCashBoxId = value);
                    },
                  ),
                  const SizedBox(height: 16),
                ],
                TextField(
                  controller: balanceController,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                    labelText: 'رصيد الافتتاح',
                    suffixText: 'ر.ي',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('إلغاء'),
              ),
              ElevatedButton(
                onPressed: () async {
                  final openingBalance = double.tryParse(balanceController.text) ?? 0.0;
                  final db = DatabaseHelper();
                  await db.insertShift({
                    'cash_box_id': selectedCashBoxId,
                    'opening_balance': openingBalance,
                    'expected_closing_balance': openingBalance,
                    'actual_closing_balance': null,
                    'total_sales': 0.0,
                    'total_expenses': 0.0,
                    'total_cash_in': 0.0,
                    'total_cash_out': 0.0,
                    'status': 'open',
                    'opened_at': DateTime.now().toIso8601String(),
                    'closed_at': null,
                    'notes': null,
                  });
                  if (mounted) {
                    Navigator.pop(ctx);
                    setState(() => _isLoading = true);
                    _loadData();
                  }
                },
                child: const Text('فتح الوردية'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════
  //  CLOSE SHIFT (with balance verification BEFORE closing)
  // ═══════════════════════════════════════════════════════════════════
  void _showCloseShiftDialog() async {
    if (_activeShift == null) return;

    final db = DatabaseHelper();
    final shiftId = _activeShift!['id'] as int;
    final cashBoxId = _activeShift!['cash_box_id'] as int?;
    final openingBalance = (_activeShift!['opening_balance'] as num?)?.toDouble() ?? 0.0;

    // Calculate shift totals from invoices
    double totalSales = 0.0;
    double totalExpenses = 0.0;

    if (cashBoxId != null) {
      final salesResult = await db.rawQuery(
        "SELECT COALESCE(SUM(total), 0.0) AS total FROM invoices WHERE type = 'sale' AND is_return = 0 AND cash_box_id = ?",
        [cashBoxId],
      );
      totalSales = (salesResult.first['total'] as num?)?.toDouble() ?? 0.0;

      final expensesResult = await db.rawQuery(
        "SELECT COALESCE(SUM(amount_base), 0.0) AS total FROM expenses WHERE cash_box_id = ?",
        [cashBoxId],
      );
      totalExpenses = (expensesResult.first['total'] as num?)?.toDouble() ?? 0.0;
    }

    final expectedClosing = openingBalance + totalSales - totalExpenses;

    final actualBalanceController = TextEditingController();
    final notesController = TextEditingController();

    if (!mounted) return;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          title: Row(
            children: [
              Icon(PhosphorIconsFill.warning, color: AppColors.warning),
              const SizedBox(width: 8),
              const Text('تأكيد إغلاق الوردية'),
            ],
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('يرجى مراجعة الأرصدة قبل الإغلاق:', style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
                const SizedBox(height: 16),
                _buildVerifyRow('رصيد الافتتاح', CurrencyFormatter.format(openingBalance)),
                _buildVerifyRow('إجمالي المبيعات', CurrencyFormatter.format(totalSales), valueColor: AppColors.success),
                _buildVerifyRow('إجمالي المصروفات', CurrencyFormatter.format(totalExpenses), valueColor: AppColors.error),
                const Divider(),
                _buildVerifyRow('الرصيد المتوقع', CurrencyFormatter.format(expectedClosing), valueColor: AppColors.primary, isBold: true),
                const SizedBox(height: 16),
                TextField(
                  controller: actualBalanceController,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                    labelText: 'الرصيد الفعلي (العدد)',
                    suffixText: 'ر.ي',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: notesController,
                  maxLines: 2,
                  decoration: InputDecoration(
                    labelText: 'ملاحظات',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
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
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.error,
                foregroundColor: Colors.white,
              ),
              onPressed: () async {
                final actualBalance = double.tryParse(actualBalanceController.text) ?? expectedClosing;
                final now = DateTime.now().toIso8601String();

                await db.updateShift(shiftId, {
                  'expected_closing_balance': expectedClosing,
                  'actual_closing_balance': actualBalance,
                  'total_sales': totalSales,
                  'total_expenses': totalExpenses,
                  'status': 'closed',
                  'closed_at': now,
                  'notes': notesController.text.isNotEmpty ? notesController.text : null,
                });

                if (mounted) {
                  Navigator.pop(ctx);
                  setState(() => _isLoading = true);
                  _loadData();
                }
              },
              child: const Text('تأكيد الإغلاق'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildVerifyRow(String label, String value, {Color? valueColor, bool isBold = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: Theme.of(context).textTheme.bodyMedium),
          Text(
            value,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              fontWeight: isBold ? FontWeight.w800 : FontWeight.w600,
              color: valueColor,
            ),
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════
  //  BUILD
  // ═══════════════════════════════════════════════════════════════════
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('الورديات'),
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
        body: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : RefreshIndicator(
                onRefresh: _loadData,
                child: SingleChildScrollView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // ── Current shift status ──────────────────────────
                      _buildCurrentShiftCard(theme, isDark),

                      const SizedBox(height: 24),

                      // ── Shift history ─────────────────────────────────
                      Text(
                        'سجل الورديات',
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 12),

                      if (_shiftHistory.isEmpty)
                        Center(
                          child: Padding(
                            padding: const EdgeInsets.all(32),
                            child: Column(
                              children: [
                                Icon(PhosphorIconsRegular.clock, size: 48, color: AppColors.textHint),
                                const SizedBox(height: 12),
                                Text('لا توجد ورديات سابقة', style: theme.textTheme.bodyLarge?.copyWith(color: AppColors.textHint)),
                              ],
                            ),
                          ),
                        )
                      else
                        ..._shiftHistory.map((shift) => _buildShiftHistoryCard(shift, theme, isDark)),
                    ],
                  ),
                ),
              ),
      ),
    );
  }

  Widget _buildCurrentShiftCard(ThemeData theme, bool isDark) {
    final hasActiveShift = _activeShift != null;
    final status = hasActiveShift ? _activeShift!['status'] as String : 'none';
    final isOpen = status == 'open';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: isOpen
            ? const LinearGradient(
                colors: [AppColors.success, AppColors.successLight],
                begin: Alignment.topRight,
                end: Alignment.bottomLeft,
              )
            : LinearGradient(
                colors: [
                  AppColors.textHint.withValues(alpha: 0.3),
                  AppColors.textHint.withValues(alpha: 0.1),
                ],
                begin: Alignment.topRight,
                end: Alignment.bottomLeft,
              ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: (isOpen ? AppColors.success : AppColors.textHint).withValues(alpha: 0.2),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                isOpen ? PhosphorIconsFill.lockOpen : PhosphorIconsFill.lockKey,
                color: Colors.white,
                size: 28,
              ),
              const SizedBox(width: 10),
              Text(
                isOpen ? 'وردية مفتوحة' : 'لا توجد وردية مفتوحة',
                style: theme.textTheme.titleLarge?.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
          if (isOpen && _activeShift != null) ...[
            const SizedBox(height: 16),
            Text(
              'رصيد الافتتاح: ${CurrencyFormatter.format((_activeShift!['opening_balance'] as num?)?.toDouble() ?? 0.0)}',
              style: theme.textTheme.bodyLarge?.copyWith(color: Colors.white70),
            ),
            const SizedBox(height: 4),
            Text(
              'تاريخ الافتتاح: ${DateFormatter.formatDateTime(DateTime.tryParse(_activeShift!['opened_at'] as String? ?? '') ?? DateTime.now())}',
              style: theme.textTheme.bodyMedium?.copyWith(color: Colors.white60),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              height: 48,
              child: ElevatedButton.icon(
                onPressed: _showCloseShiftDialog,
                icon: const Icon(PhosphorIconsRegular.lockKey, size: 20),
                label: const Text('إغلاق الوردية'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.white,
                  foregroundColor: AppColors.error,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ),
          ] else ...[
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              height: 48,
              child: ElevatedButton.icon(
                onPressed: _showOpenShiftDialog,
                icon: const Icon(PhosphorIconsRegular.lockOpen, size: 20),
                label: const Text('فتح وردية جديدة'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.white,
                  foregroundColor: AppColors.success,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildShiftHistoryCard(Map<String, dynamic> shift, ThemeData theme, bool isDark) {
    final openingBalance = (shift['opening_balance'] as num?)?.toDouble() ?? 0.0;
    final expectedClosing = (shift['expected_closing_balance'] as num?)?.toDouble() ?? 0.0;
    final actualClosing = (shift['actual_closing_balance'] as num?)?.toDouble();
    final totalSales = (shift['total_sales'] as num?)?.toDouble() ?? 0.0;
    final totalExpenses = (shift['total_expenses'] as num?)?.toDouble() ?? 0.0;
    final openedAt = shift['opened_at'] as String? ?? '';
    final closedAt = shift['closed_at'] as String? ?? '';
    final hasDiscrepancy = actualClosing != null && (actualClosing - expectedClosing).abs() > 0.01;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  DateFormatter.formatDateTime(DateTime.tryParse(openedAt) ?? DateTime.now()),
                  style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: hasDiscrepancy ? AppColors.warningLight : AppColors.successLight,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    hasDiscrepancy ? 'فرق' : 'مطابق',
                    style: TextStyle(
                      color: hasDiscrepancy ? AppColors.warning : AppColors.success,
                      fontWeight: FontWeight.w700,
                      fontSize: 12,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('الافتتاح', style: theme.textTheme.labelSmall?.copyWith(color: AppColors.textHint)),
                      Text(CurrencyFormatter.format(openingBalance), style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
                    ],
                  ),
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('المبيعات', style: theme.textTheme.labelSmall?.copyWith(color: AppColors.textHint)),
                      Text(CurrencyFormatter.format(totalSales), style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600, color: AppColors.success)),
                    ],
                  ),
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('المصروفات', style: theme.textTheme.labelSmall?.copyWith(color: AppColors.textHint)),
                      Text(CurrencyFormatter.format(totalExpenses), style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600, color: AppColors.error)),
                    ],
                  ),
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('الفعلي', style: theme.textTheme.labelSmall?.copyWith(color: AppColors.textHint)),
                      Text(
                        actualClosing != null ? CurrencyFormatter.format(actualClosing) : '—',
                        style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            if (closedAt.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                'أُغلقت: ${DateFormatter.formatDateTime(DateTime.tryParse(closedAt) ?? DateTime.now())}',
                style: theme.textTheme.labelSmall?.copyWith(color: AppColors.textHint),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
