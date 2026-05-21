import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../core/extensions/context_extensions.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/design_system.dart';
import '../../../core/utils/currency_formatter.dart';
import '../../../core/utils/date_formatter.dart';
import '../../../data/datasources/database_helper.dart';
import '../../../data/models/shift_model.dart';

class ShiftsScreen extends StatefulWidget {
  const ShiftsScreen({super.key});

  @override
  State<ShiftsScreen> createState() => _ShiftsScreenState();
}

class _ShiftsScreenState extends State<ShiftsScreen> {
  List<Map<String, dynamic>> _allShifts = [];
  bool _isLoading = true;
  Shift? _activeShift;
  String? _activeShiftCashBoxName;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    try {
      final db = DatabaseHelper();
      final shiftsRaw = await db.getAllShifts();
      
      Shift? active;
      String? activeCashBoxName;
      
      for (final map in shiftsRaw) {
        if (map['status'] == 'open') {
          active = Shift.fromMap(map);
          activeCashBoxName = map['cash_box_name'] as String?;
          break;
        }
      }
      
      setState(() {
        _allShifts = shiftsRaw;
        _activeShift = active;
        _activeShiftCashBoxName = activeCashBoxName;
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
    }
  }

  String _getCurrencySymbol(String? currency) {
    switch (currency) {
      case 'SAR': return 'ر.س';
      case 'USD': return r'$';
      case 'YER': default: return 'ر.ي';
    }
  }

  String _formatDuration(DateTime openedAt) {
    final diff = DateTime.now().difference(openedAt);
    final hours = diff.inHours;
    final minutes = diff.inMinutes.remainder(60);
    if (hours > 0) {
      return '$hours ساعة $minutes دقيقة';
    }
    return '$minutes دقيقة';
  }

  // ────────────────────────────────────────────────────────────────
  //  OPEN SHIFT DIALOG
  // ────────────────────────────────────────────────────────────────

  Future<void> _showOpenShiftDialog() async {
    if (_activeShift != null) return;

    final db = DatabaseHelper();
    final cashBoxes = await db.getAllCashBoxes();
    
    if (!mounted) return;
    if (cashBoxes.isEmpty) {
      context.showErrorSnackBar('لا توجد صناديق. أضف صندوق أولاً');
      return;
    }

    int? selectedCashBoxId = cashBoxes.first['id'] as int?;
    final openingAmountController = TextEditingController();
    final notesController = TextEditingController();
    String selectedCurrency = 'YER';
    final formKey = GlobalKey<FormState>();

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(DesignSystem.radius20)),
      ),
      builder: (sheetContext) => Directionality(
        textDirection: TextDirection.rtl,
        child: StatefulBuilder(
          builder: (context, setSheetState) {
            final bottomInset = MediaQuery.of(context).viewInsets.bottom;
            return Padding(
              padding: EdgeInsets.only(bottom: bottomInset),
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(DesignSystem.spacing20),
                child: Form(
                  key: formKey,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // Handle
                      Center(
                        child: Container(
                          width: 40, height: 4,
                          decoration: BoxDecoration(
                            color: AppColors.textHint.withValues(alpha: 0.3),
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                      ),
                      const SizedBox(height: DesignSystem.spacing16),
                      
                      // Title
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: AppColors.successLight,
                              borderRadius: BorderRadius.circular(DesignSystem.radius12),
                            ),
                            child: const Icon(PhosphorIconsRegular.arrowCircleUp, color: AppColors.success, size: 22),
                          ),
                          const SizedBox(width: DesignSystem.spacing12),
                          Text('فتح وردية جديدة', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
                        ],
                      ),
                      const SizedBox(height: DesignSystem.spacing24),

                      // Cash box selector
                      Text('الصندوق', style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600)),
                      const SizedBox(height: DesignSystem.spacing8),
                      DropdownButtonFormField<int>(
                        initialValue: selectedCashBoxId,
                        decoration: InputDecoration(
                          prefixIcon: const Icon(PhosphorIconsRegular.vault, size: 20),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(DesignSystem.radius12)),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
                        ),
                        items: cashBoxes.map<DropdownMenuItem<int>>((cb) {
                          return DropdownMenuItem<int>(
                            value: cb['id'] as int,
                            child: Text(cb['name'] as String? ?? ''),
                          );
                        }).toList(),
                        onChanged: (v) => setSheetState(() => selectedCashBoxId = v),
                        validator: (v) => v == null ? 'اختر الصندوق' : null,
                      ),
                      const SizedBox(height: DesignSystem.spacing16),

                      // Currency selector
                      Text('العملة', style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600)),
                      const SizedBox(height: DesignSystem.spacing8),
                      Row(
                        children: ['YER', 'SAR', 'USD'].map((c) {
                          final isSelected = selectedCurrency == c;
                          return Padding(
                            padding: const EdgeInsets.only(left: 8),
                            child: ChoiceChip(
                              label: Text('${_getCurrencySymbol(c)} $c'),
                              selected: isSelected,
                              onSelected: (_) => setSheetState(() => selectedCurrency = c),
                              selectedColor: AppColors.primary.withValues(alpha: 0.15),
                              side: BorderSide(color: isSelected ? AppColors.primary : AppColors.divider),
                              labelStyle: TextStyle(
                                color: isSelected ? AppColors.primary : AppColors.textSecondary,
                                fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                              ),
                              visualDensity: VisualDensity.compact,
                            ),
                          );
                        }).toList(),
                      ),
                      const SizedBox(height: DesignSystem.spacing16),

                      // Opening amount
                      Text('مبلغ الافتتاح', style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600)),
                      const SizedBox(height: DesignSystem.spacing8),
                      TextFormField(
                        controller: openingAmountController,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        decoration: InputDecoration(
                          prefixIcon: const Icon(PhosphorIconsRegular.currencyCircleDollar, size: 20),
                          suffixText: _getCurrencySymbol(selectedCurrency),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(DesignSystem.radius12)),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
                          hintText: '0.00',
                        ),
                        validator: (v) {
                          if (v == null || v.trim().isEmpty) return 'أدخل مبلغ الافتتاح';
                          if (double.tryParse(v) == null) return 'مبلغ غير صالح';
                          return null;
                        },
                      ),
                      const SizedBox(height: DesignSystem.spacing16),

                      // Notes
                      Text('ملاحظات', style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600)),
                      const SizedBox(height: DesignSystem.spacing8),
                      TextFormField(
                        controller: notesController,
                        maxLines: 2,
                        decoration: InputDecoration(
                          prefixIcon: const Padding(
                            padding: EdgeInsets.only(bottom: 28),
                            child: Icon(PhosphorIconsRegular.note, size: 20),
                          ),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(DesignSystem.radius12)),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
                          hintText: 'ملاحظات اختيارية...',
                        ),
                      ),
                      const SizedBox(height: DesignSystem.spacing24),

                      // Save button
                      FilledButton.icon(
                        onPressed: () async {
                          if (!formKey.currentState!.validate()) return;
                          if (selectedCashBoxId == null) return;

                          final nav = Navigator.of(context);
                          final messenger = ScaffoldMessenger.of(context);
                          final now = DateTime.now();
                          final shiftNumber = await db.getNextShiftNumber();
                          final openingAmount = double.parse(openingAmountController.text.trim());

                          final shiftMap = {
                            'shift_number': shiftNumber,
                            'cash_box_id': selectedCashBoxId,
                            'opening_amount': openingAmount,
                            'expected_amount': openingAmount,
                            'status': 'open',
                            'opened_at': now.toIso8601String(),
                            'notes': notesController.text.trim().isEmpty ? null : notesController.text.trim(),
                            'total_sales': 0.0,
                            'total_returns': 0.0,
                            'total_discounts': 0.0,
                            'transaction_count': 0,
                            'currency': selectedCurrency,
                            'created_at': now.toIso8601String(),
                            'updated_at': now.toIso8601String(),
                          };

                          await db.openShift(shiftMap);

                          if (!mounted) return;
                          nav.pop();
                          messenger.showSnackBar(
                            SnackBar(content: Text('تم فتح الوردية $shiftNumber'), backgroundColor: AppColors.success),
                          );
                          _loadData();
                        },
                        icon: const Icon(PhosphorIconsRegular.arrowCircleUp, size: 20),
                        label: const Text('فتح الوردية', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                        style: FilledButton.styleFrom(
                          backgroundColor: AppColors.success,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(DesignSystem.radius12)),
                        ),
                      ),
                      SizedBox(height: MediaQuery.of(context).viewPadding.bottom + 8),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  // ────────────────────────────────────────────────────────────────
  //  CLOSE SHIFT DIALOG
  // ────────────────────────────────────────────────────────────────

  Future<void> _showCloseShiftDialog() async {
    if (_activeShift == null) return;

    final shift = _activeShift!;
    final closingAmountController = TextEditingController();
    final notesController = TextEditingController();
    final symbol = _getCurrencySymbol(shift.currency);
    final expectedAmount = shift.calculatedExpected;
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(DesignSystem.radius20)),
      ),
      builder: (sheetContext) => Directionality(
        textDirection: TextDirection.rtl,
        child: StatefulBuilder(
          builder: (context, setSheetState) {
            final bottomInset = MediaQuery.of(context).viewInsets.bottom;
            final actualClosing = double.tryParse(closingAmountController.text) ?? 0;
            final currentDiff = actualClosing - expectedAmount;

            return Padding(
              padding: EdgeInsets.only(bottom: bottomInset),
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(DesignSystem.spacing20),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Handle
                    Center(
                      child: Container(
                        width: 40, height: 4,
                        decoration: BoxDecoration(
                          color: AppColors.textHint.withValues(alpha: 0.3),
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                    const SizedBox(height: DesignSystem.spacing16),

                    // Title
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: AppColors.errorLight,
                            borderRadius: BorderRadius.circular(DesignSystem.radius12),
                          ),
                          child: const Icon(PhosphorIconsRegular.arrowCircleDown, color: AppColors.error, size: 22),
                        ),
                        const SizedBox(width: DesignSystem.spacing12),
                        Expanded(
                          child: Text('إغلاق الوردية ${shift.shiftNumber}', 
                            style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
                        ),
                      ],
                    ),
                    const SizedBox(height: DesignSystem.spacing20),

                    // Summary card
                    Container(
                      padding: const EdgeInsets.all(DesignSystem.spacing16),
                      decoration: BoxDecoration(
                        color: AppColors.surfaceVariant.withValues(alpha: 0.6),
                        borderRadius: BorderRadius.circular(DesignSystem.radius12),
                        border: Border.all(color: AppColors.divider),
                      ),
                      child: Column(
                        children: [
                          _buildSummaryRow('مبلغ الافتتاح', CurrencyFormatter.format(shift.openingAmount, symbol: symbol)),
                          const Divider(height: 20),
                          _buildSummaryRow('إجمالي المبيعات', CurrencyFormatter.format(shift.totalSales, symbol: symbol),
                              valueColor: AppColors.success),
                          const Divider(height: 20),
                          _buildSummaryRow('إجمالي المرتجعات', CurrencyFormatter.format(shift.totalReturns, symbol: symbol),
                              valueColor: AppColors.error),
                          const Divider(height: 20),
                          _buildSummaryRow('إجمالي الخصومات', CurrencyFormatter.format(shift.totalDiscounts, symbol: symbol),
                              valueColor: AppColors.warning),
                          const Divider(height: 20),
                          _buildSummaryRow('المبلغ المتوقع', CurrencyFormatter.format(expectedAmount, symbol: symbol),
                              valueColor: AppColors.primary, isBold: true),
                          const Divider(height: 20),
                          _buildSummaryRow('عدد المعاملات', '${shift.transactionCount}'),
                        ],
                      ),
                    ),
                    const SizedBox(height: DesignSystem.spacing20),

                    // Actual closing amount
                    Text('المبلغ الفعلي (العد)', style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600)),
                    const SizedBox(height: DesignSystem.spacing8),
                    TextFormField(
                      controller: closingAmountController,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      decoration: InputDecoration(
                        prefixIcon: const Icon(PhosphorIconsRegular.currencyCircleDollar, size: 20),
                        suffixText: symbol,
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(DesignSystem.radius12)),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
                        hintText: '0.00',
                      ),
                      onChanged: (_) => setSheetState(() {}),
                    ),
                    const SizedBox(height: DesignSystem.spacing12),

                    // Difference display
                    Container(
                      padding: const EdgeInsets.all(DesignSystem.spacing12),
                      decoration: BoxDecoration(
                        color: currentDiff.abs() < 0.005
                            ? AppColors.successLight
                            : AppColors.errorLight,
                        borderRadius: BorderRadius.circular(DesignSystem.radius12),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text('الفرق', style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600)),
                          Text(
                            currentDiff.abs() < 0.005
                                ? 'متوازن ✓'
                                : '${currentDiff > 0 ? "+" : ""}${CurrencyFormatter.format(currentDiff, symbol: symbol)}',
                            style: TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 16,
                              color: currentDiff.abs() < 0.005
                                  ? AppColors.success
                                  : AppColors.error,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: DesignSystem.spacing16),

                    // Notes
                    Text('ملاحظات', style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600)),
                    const SizedBox(height: DesignSystem.spacing8),
                    TextFormField(
                      controller: notesController,
                      maxLines: 2,
                      decoration: InputDecoration(
                        prefixIcon: const Padding(
                          padding: EdgeInsets.only(bottom: 28),
                          child: Icon(PhosphorIconsRegular.note, size: 20),
                        ),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(DesignSystem.radius12)),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
                        hintText: 'ملاحظات اختيارية...',
                      ),
                    ),
                    const SizedBox(height: DesignSystem.spacing24),

                    // Close button
                    FilledButton.icon(
                      onPressed: () async {
                        if (closingAmountController.text.trim().isEmpty) {
                          context.showErrorSnackBar('أدخل المبلغ الفعلي');
                          return;
                        }
                        final actualAmount = double.tryParse(closingAmountController.text.trim());
                        if (actualAmount == null) {
                          context.showErrorSnackBar('مبلغ غير صالح');
                          return;
                        }

                        final nav = Navigator.of(context);
                        final messenger = ScaffoldMessenger.of(context);
                        final now = DateTime.now();
                        final diff = actualAmount - expectedAmount;

                        final closeData = {
                          'closing_amount': actualAmount,
                          'expected_amount': expectedAmount,
                          'difference': diff,
                          'status': 'closed',
                          'closed_at': now.toIso8601String(),
                          'notes': notesController.text.trim().isEmpty
                              ? (shift.notes ?? '')
                              : '${shift.notes ?? ''}\nإغلاق: ${notesController.text.trim()}',
                          'updated_at': now.toIso8601String(),
                        };

                        final db = DatabaseHelper();
                        await db.closeShift(shift.id!, closeData);

                        if (!mounted) return;
                        nav.pop();
                        messenger.showSnackBar(
                          SnackBar(content: Text('تم إغلاق الوردية ${shift.shiftNumber}'), backgroundColor: AppColors.success),
                        );
                        _loadData();
                      },
                      icon: const Icon(PhosphorIconsRegular.arrowCircleDown, size: 20),
                      label: const Text('إغلاق الوردية', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                      style: FilledButton.styleFrom(
                        backgroundColor: AppColors.error,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(DesignSystem.radius12)),
                      ),
                    ),
                    SizedBox(height: MediaQuery.of(context).viewPadding.bottom + 8),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildSummaryRow(String label, String value, {Color? valueColor, bool isBold = false}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: TextStyle(
          color: AppColors.textSecondary,
          fontSize: 14,
          fontWeight: isBold ? FontWeight.w600 : FontWeight.w400,
        )),
        Text(value, style: TextStyle(
          color: valueColor ?? AppColors.textPrimary,
          fontSize: 14,
          fontWeight: isBold ? FontWeight.w700 : FontWeight.w500,
        )),
      ],
    );
  }

  // ────────────────────────────────────────────────────────────────
  //  SHIFT DETAIL / Z-REPORT
  // ────────────────────────────────────────────────────────────────

  void _showShiftDetail(Map<String, dynamic> shiftMap) {
    final shift = Shift.fromMap(shiftMap);
    final cashBoxName = shiftMap['cash_box_name'] as String? ?? '';
    final symbol = _getCurrencySymbol(shift.currency);
    final expectedAmount = shift.calculatedExpected;
    final diff = shift.difference ?? (shift.closingAmount != null ? shift.closingAmount! - expectedAmount : null);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(DesignSystem.radius20)),
      ),
      builder: (context) => Directionality(
        textDirection: TextDirection.rtl,
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(DesignSystem.spacing20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Handle
              Center(
                child: Container(
                  width: 40, height: 4,
                  decoration: BoxDecoration(
                    color: AppColors.textHint.withValues(alpha: 0.3),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: DesignSystem.spacing16),

              // Z-Report header
              Container(
                padding: const EdgeInsets.all(DesignSystem.spacing16),
                decoration: BoxDecoration(
                  gradient: AppColors.primaryGradient,
                  borderRadius: BorderRadius.circular(DesignSystem.radius16),
                ),
                child: Column(
                  children: [
                    const Icon(PhosphorIconsRegular.receipt, color: Colors.white, size: 32),
                    const SizedBox(height: 8),
                    Text('تقرير Z - ${shift.shiftNumber}', style: const TextStyle(
                      color: Colors.white, fontSize: 20, fontWeight: FontWeight.w700,
                    )),
                    const SizedBox(height: 4),
                    Text(cashBoxName, style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.9), fontSize: 14,
                    )),
                  ],
                ),
              ),
              const SizedBox(height: DesignSystem.spacing20),

              // Report details
              Container(
                padding: const EdgeInsets.all(DesignSystem.spacing16),
                decoration: BoxDecoration(
                  color: AppColors.surfaceVariant.withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(DesignSystem.radius12),
                  border: Border.all(color: AppColors.divider),
                ),
                child: Column(
                  children: [
                    _buildSummaryRow('الحالة', Shift.getStatusAr(shift.status),
                        valueColor: shift.status == 'open' ? AppColors.success : AppColors.textSecondary),
                    const Divider(height: 20),
                    _buildSummaryRow('تاريخ الافتتاح', DateFormatter.formatDateTime(shift.openedAt)),
                    if (shift.closedAt != null) ...[
                      const Divider(height: 20),
                      _buildSummaryRow('تاريخ الإغلاق', DateFormatter.formatDateTime(shift.closedAt!)),
                    ],
                    const Divider(height: 20),
                    _buildSummaryRow('العملة', '${_getCurrencySymbol(shift.currency)} ${shift.currency}'),
                    const Divider(height: 20),
                    _buildSummaryRow('مبلغ الافتتاح', CurrencyFormatter.format(shift.openingAmount, symbol: symbol)),
                    const Divider(height: 20),
                    _buildSummaryRow('إجمالي المبيعات', CurrencyFormatter.format(shift.totalSales, symbol: symbol),
                        valueColor: AppColors.success),
                    const Divider(height: 20),
                    _buildSummaryRow('إجمالي المرتجعات', CurrencyFormatter.format(shift.totalReturns, symbol: symbol),
                        valueColor: AppColors.error),
                    const Divider(height: 20),
                    _buildSummaryRow('إجمالي الخصومات', CurrencyFormatter.format(shift.totalDiscounts, symbol: symbol),
                        valueColor: AppColors.warning),
                    const Divider(height: 20),
                    _buildSummaryRow('المبلغ المتوقع', CurrencyFormatter.format(expectedAmount, symbol: symbol),
                        valueColor: AppColors.primary, isBold: true),
                    if (shift.closingAmount != null) ...[
                      const Divider(height: 20),
                      _buildSummaryRow('المبلغ الفعلي', CurrencyFormatter.format(shift.closingAmount!, symbol: symbol),
                          isBold: true),
                    ],
                    if (diff != null) ...[
                      const Divider(height: 20),
                      _buildSummaryRow(
                        'الفرق',
                        diff.abs() < 0.005
                            ? 'متوازن ✓'
                            : CurrencyFormatter.format(diff, symbol: symbol),
                        valueColor: diff.abs() < 0.005 ? AppColors.success : AppColors.error,
                        isBold: true,
                      ),
                    ],
                    const Divider(height: 20),
                    _buildSummaryRow('عدد المعاملات', '${shift.transactionCount}'),
                    if (shift.notes != null && shift.notes!.isNotEmpty) ...[
                      const Divider(height: 20),
                      Align(
                        alignment: Alignment.centerRight,
                        child: Text('ملاحظات:', style: TextStyle(
                          color: AppColors.textSecondary, fontSize: 13, fontWeight: FontWeight.w600,
                        )),
                      ),
                      const SizedBox(height: 4),
                      Align(
                        alignment: Alignment.centerRight,
                        child: Text(shift.notes!, style: const TextStyle(fontSize: 13)),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: DesignSystem.spacing20),

              // Close button
              OutlinedButton(
                onPressed: () => Navigator.pop(context),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(DesignSystem.radius12)),
                ),
                child: const Text('إغلاق التقرير'),
              ),
              SizedBox(height: MediaQuery.of(context).viewPadding.bottom + 8),
            ],
          ),
        ),
      ),
    );
  }

  // ────────────────────────────────────────────────────────────────
  //  BUILD
  // ────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final bottomPadding = MediaQuery.of(context).viewPadding.bottom;
    final closedShifts = _allShifts.where((s) => s['status'] != 'open').toList();

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('الورديات'),
          actions: [
            if (_activeShift != null)
              IconButton(
                icon: const Icon(PhosphorIconsRegular.arrowCircleDown),
                tooltip: 'إغلاق الوردية',
                onPressed: _showCloseShiftDialog,
              ),
          ],
        ),
        body: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : RefreshIndicator(
                onRefresh: _loadData,
                child: CustomScrollView(
                  slivers: [
                    // Active shift card
                    SliverToBoxAdapter(child: _buildActiveShiftCard(theme, isDark)),

                    // History header
                    if (closedShifts.isNotEmpty)
                      SliverToBoxAdapter(
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(
                            DesignSystem.spacing16,
                            DesignSystem.spacing20,
                            DesignSystem.spacing16,
                            DesignSystem.spacing8,
                          ),
                          child: Row(
                            children: [
                              const Icon(PhosphorIconsRegular.clockCounterClockwise, size: 18, color: AppColors.textSecondary),
                              const SizedBox(width: 6),
                              Text('سجل الورديات المغلقة',
                                style: theme.textTheme.titleSmall?.copyWith(
                                  color: AppColors.textSecondary,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const Spacer(),
                              Text('${closedShifts.length} وردية',
                                style: theme.textTheme.bodySmall?.copyWith(color: AppColors.textTertiary),
                              ),
                            ],
                          ),
                        ),
                      ),

                    // Closed shifts list
                    closedShifts.isEmpty
                        ? SliverToBoxAdapter(child: _buildEmptyHistory(theme, isDark))
                        : SliverList(
                            delegate: SliverChildBuilderDelegate(
                              (context, index) => _buildClosedShiftCard(closedShifts[index], theme, isDark),
                              childCount: closedShifts.length,
                            ),
                          ),

                    // Bottom padding
                    SliverToBoxAdapter(child: SizedBox(height: 100 + bottomPadding)),
                  ],
                ),
              ),
        floatingActionButton: _activeShift == null
            ? FloatingActionButton(
                onPressed: _showOpenShiftDialog,
                backgroundColor: AppColors.success,
                tooltip: 'فتح وردية جديدة',
                child: const Icon(PhosphorIconsFill.plus, color: Colors.white),
              )
            : null,
      ),
    );
  }

  // ────────────────────────────────────────────────────────────────
  //  ACTIVE SHIFT CARD
  // ────────────────────────────────────────────────────────────────

  Widget _buildActiveShiftCard(ThemeData theme, bool isDark) {
    if (_activeShift == null) {
      return Container(
        margin: const EdgeInsets.all(DesignSystem.spacing16),
        padding: const EdgeInsets.all(DesignSystem.spacing24),
        decoration: BoxDecoration(
          gradient: AppColors.primaryGradient,
          borderRadius: BorderRadius.circular(DesignSystem.radius16),
          boxShadow: DesignSystem.cardShadow(isLight: !isDark),
        ),
        child: Column(
          children: [
            const Icon(PhosphorIconsRegular.vault, color: Colors.white, size: 40),
            const SizedBox(height: DesignSystem.spacing12),
            const Text('لا توجد وردية مفتوحة', style: TextStyle(
              color: Colors.white, fontSize: 18, fontWeight: FontWeight.w600,
            )),
            const SizedBox(height: 8),
            Text('اضغط + لفتح وردية جديدة', style: TextStyle(
              color: Colors.white.withValues(alpha: 0.8), fontSize: 14,
            )),
          ],
        ),
      );
    }

    final shift = _activeShift!;
    final symbol = _getCurrencySymbol(shift.currency);
    final duration = _formatDuration(shift.openedAt);

    return Container(
      margin: const EdgeInsets.all(DesignSystem.spacing16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF43A047), Color(0xFF66BB6A)],
          begin: Alignment.topRight,
          end: Alignment.bottomLeft,
        ),
        borderRadius: BorderRadius.circular(DesignSystem.radius16),
        boxShadow: DesignSystem.elevatedShadow(isLight: !isDark),
      ),
      child: Column(
        children: [
          // Header
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.25),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(PhosphorIconsFill.circle, color: Colors.white, size: 8),
                      SizedBox(width: 6),
                      Text('مفتوحة', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 12)),
                    ],
                  ),
                ),
                const Spacer(),
                Text(shift.shiftNumber, style: const TextStyle(
                  color: Colors.white, fontWeight: FontWeight.w700, fontSize: 14,
                )),
              ],
            ),
          ),

          // Body
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
            child: Column(
              children: [
                Row(
                  children: [
                    const Icon(PhosphorIconsRegular.vault, color: Colors.white70, size: 16),
                    const SizedBox(width: 6),
                    Text(_activeShiftCashBoxName ?? '', style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.9), fontSize: 14,
                    )),
                    const Spacer(),
                    const Icon(PhosphorIconsRegular.timer, color: Colors.white70, size: 16),
                    const SizedBox(width: 6),
                    Text(duration, style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.9), fontSize: 13,
                    )),
                  ],
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('الافتتاح', style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.7), fontSize: 12,
                          )),
                          const SizedBox(height: 2),
                          Text(CurrencyFormatter.format(shift.openingAmount, symbol: symbol),
                            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 16),
                          ),
                        ],
                      ),
                    ),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('المبيعات', style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.7), fontSize: 12,
                          )),
                          const SizedBox(height: 2),
                          Text(CurrencyFormatter.format(shift.totalSales, symbol: symbol),
                            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 16),
                          ),
                        ],
                      ),
                    ),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('المعاملات', style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.7), fontSize: 12,
                          )),
                          const SizedBox(height: 2),
                          Text('${shift.transactionCount}',
                            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 16),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),

                // Close button
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: _showCloseShiftDialog,
                    icon: const Icon(PhosphorIconsRegular.arrowCircleDown, size: 18),
                    label: const Text('إغلاق الوردية'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.white,
                      side: const BorderSide(color: Colors.white54),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(DesignSystem.radius12)),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ────────────────────────────────────────────────────────────────
  //  CLOSED SHIFT CARD
  // ────────────────────────────────────────────────────────────────

  Widget _buildClosedShiftCard(Map<String, dynamic> shiftMap, ThemeData theme, bool isDark) {
    final shift = Shift.fromMap(shiftMap);
    final cashBoxName = shiftMap['cash_box_name'] as String? ?? '';
    final symbol = _getCurrencySymbol(shift.currency);
    final diff = shift.difference ?? 0.0;
    final isBalanced = diff.abs() < 0.005;

    return Container(
      margin: const EdgeInsets.symmetric(
        horizontal: DesignSystem.spacing16,
        vertical: DesignSystem.spacing6,
      ),
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkSurface : AppColors.surface,
        borderRadius: BorderRadius.circular(DesignSystem.radius14),
        boxShadow: DesignSystem.cardShadow(isLight: !isDark),
        border: Border.all(
          color: isDark ? AppColors.darkDivider : AppColors.divider,
          width: 0.5,
        ),
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(DesignSystem.radius14),
        child: InkWell(
          borderRadius: BorderRadius.circular(DesignSystem.radius14),
          onTap: () => _showShiftDetail(shiftMap),
          child: Padding(
            padding: const EdgeInsets.all(DesignSystem.spacing16),
            child: Column(
              children: [
                // Row 1: Shift number, status, cash box
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: AppColors.textTertiary.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(DesignSystem.radius8),
                      ),
                      child: const Icon(PhosphorIconsRegular.archive, size: 18, color: AppColors.textTertiary),
                    ),
                    const SizedBox(width: DesignSystem.spacing10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(shift.shiftNumber, style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
                          Text(cashBoxName, style: theme.textTheme.bodySmall?.copyWith(color: AppColors.textSecondary)),
                        ],
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: AppColors.textTertiary.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(PhosphorIconsFill.circle, size: 6, color: AppColors.textTertiary),
                          SizedBox(width: 4),
                          Text('مغلقة', style: TextStyle(fontSize: 11, color: AppColors.textTertiary, fontWeight: FontWeight.w600)),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: DesignSystem.spacing12),

                // Row 2: Dates
                Row(
                  children: [
                    const Icon(PhosphorIconsRegular.calendarBlank, size: 14, color: AppColors.textTertiary),
                    const SizedBox(width: 4),
                    Text(
                      '${DateFormatter.formatDateTime(shift.openedAt)} → ${shift.closedAt != null ? DateFormatter.formatDateTime(shift.closedAt!) : '-'}',
                      style: theme.textTheme.bodySmall?.copyWith(color: AppColors.textSecondary),
                    ),
                  ],
                ),
                const SizedBox(height: DesignSystem.spacing10),

                // Row 3: Sales and difference
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('المبيعات', style: theme.textTheme.bodySmall?.copyWith(color: AppColors.textTertiary, fontSize: 11)),
                          const SizedBox(height: 2),
                          Text(CurrencyFormatter.format(shift.totalSales, symbol: symbol),
                            style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
                        ],
                      ),
                    ),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('الفرق', style: theme.textTheme.bodySmall?.copyWith(color: AppColors.textTertiary, fontSize: 11)),
                          const SizedBox(height: 2),
                          Text(
                            isBalanced
                                ? 'متوازن ✓'
                                : CurrencyFormatter.format(diff, symbol: symbol),
                            style: TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 14,
                              color: isBalanced ? AppColors.success : AppColors.error,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ────────────────────────────────────────────────────────────────
  //  EMPTY STATE
  // ────────────────────────────────────────────────────────────────

  Widget _buildEmptyHistory(ThemeData theme, bool isDark) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: DesignSystem.spacing40),
      child: Column(
        children: [
          Icon(PhosphorIconsRegular.archive, size: 56, color: AppColors.textHint.withValues(alpha: 0.5)),
          const SizedBox(height: DesignSystem.spacing12),
          Text('لا توجد ورديات مغلقة بعد', style: theme.textTheme.titleMedium?.copyWith(color: AppColors.textTertiary)),
          const SizedBox(height: 4),
          Text('ستظهر هنا الورديات بعد إغلاقها', style: theme.textTheme.bodySmall?.copyWith(color: AppColors.textTertiary)),
        ],
      ),
    );
  }
}
