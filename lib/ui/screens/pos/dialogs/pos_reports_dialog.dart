import 'package:flutter/material.dart';

import 'package:firstpro/core/constants/app_constants.dart';
import 'package:firstpro/core/extensions/context_extensions.dart';
import 'package:firstpro/core/helpers/currency_constants.dart';
import 'package:firstpro/core/theme/app_colors.dart';
import 'package:firstpro/core/utils/currency_formatter.dart';
import 'package:firstpro/core/utils/money_helper.dart';
import 'package:firstpro/core/di/service_locator.dart';
import 'package:firstpro/core/viewmodels/pos_viewmodel.dart';
import 'package:firstpro/data/datasources/services/shift_service.dart';

/// Helper to build a report row.
Widget reportRow(BuildContext context, String label, String value,
    {Color? valueColor, bool isBold = false}) {
  return Padding(
    padding: const EdgeInsets.symmetric(vertical: 3),
    child: Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label,
            style: context.textTheme.bodyMedium
                ?.copyWith(color: context.textSecondary)),
        Text(
          value,
          style: context.textTheme.bodyMedium?.copyWith(
            fontWeight: isBold ? FontWeight.w800 : FontWeight.w600,
            color: valueColor ?? context.textPrimary,
          ),
        ),
      ],
    ),
  );
}

/// Shows the X-Report (mid-shift report) bottom sheet.
Future<void> showXReport(BuildContext context, PosViewModel vm) async {
  final shift = vm.activeShift;
  if (shift == null) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
          content: Text('لا توجد وردية نشطة'),
          backgroundColor: AppColors.warning),
    );
    return;
  }
  final openingAmount = MoneyHelper.readMoney(shift['opening_amount']);
  final totalSales = MoneyHelper.readMoney(shift['total_sales']);
  final totalReturns = MoneyHelper.readMoney(shift['total_returns']);
  final totalDiscounts = MoneyHelper.readMoney(shift['total_discounts']);
  final transactionCount = (shift['transaction_count'] as num?)?.toInt() ?? 0;
  final expectedAmount =
      openingAmount + totalSales - totalReturns - totalDiscounts;

  await showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    builder: (ctx) => Directionality(
      textDirection: TextDirection.rtl,
      child: Padding(
        padding: EdgeInsets.only(
          left: 20,
          right: 20,
          top: 20,
          bottom: MediaQuery.of(ctx).viewInsets.bottom +
              MediaQuery.of(ctx).viewPadding.bottom +
              20,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: AppColors.divider,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: AppColors.info.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(Icons.bar_chart,
                      color: AppColors.info, size: 24),
                ),
                const SizedBox(width: 12),
                Text(
                  'تقرير X – منتصف الوردية',
                  style: context.textTheme.titleLarge
                      ?.copyWith(fontWeight: FontWeight.w800),
                ),
              ],
            ),
            const SizedBox(height: 20),
            reportRow(context, 'رقم الوردية',
                shift['shift_number']?.toString() ?? '-'),
            reportRow(context, 'الكاشير', vm.cashierName),
            reportRow(context, 'الصندوق', vm.shiftCashBoxName),
            reportRow(context, 'المدة', vm.formattedShiftDuration),
            const Divider(height: 24),
            reportRow(context, 'رصيد الافتتاح',
                CurrencyFormatter.format(openingAmount),
                valueColor: AppColors.primary),
            reportRow(context, 'إجمالي المبيعات',
                CurrencyFormatter.format(totalSales),
                valueColor: AppColors.success),
            reportRow(context, 'إجمالي المرتجعات',
                CurrencyFormatter.format(totalReturns),
                valueColor: AppColors.error),
            reportRow(context, 'إجمالي الخصومات',
                CurrencyFormatter.format(totalDiscounts),
                valueColor: AppColors.warning),
            const Divider(height: 24),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(12),
                border:
                    Border.all(color: AppColors.primary.withValues(alpha: 0.2)),
              ),
              child: Column(
                children: [
                  reportRow(context, 'المتوقع في الصندوق',
                      CurrencyFormatter.format(expectedAmount),
                      valueColor: AppColors.primary, isBold: true),
                  const SizedBox(height: 6),
                  reportRow(
                      context, 'عدد المعاملات', transactionCount.toString()),
                ],
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              height: 48,
              child: ElevatedButton(
                onPressed: () => Navigator.pop(ctx),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.info,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
                child: const Text('إغلاق التقرير',
                    style: TextStyle(fontWeight: FontWeight.w700)),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

/// Shows the Z-Report / Close Shift bottom sheet.
Future<void> showZReport(BuildContext context, PosViewModel vm) async {
  final shift = vm.activeShift;
  if (shift == null) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
          content: Text('لا توجد وردية نشطة'),
          backgroundColor: AppColors.warning),
    );
    return;
  }
  final shiftId = shift['id'] as int;
  final openingAmount = MoneyHelper.readMoney(shift['opening_amount']);
  final totalSales = MoneyHelper.readMoney(shift['total_sales']);
  final totalReturns = MoneyHelper.readMoney(shift['total_returns']);
  final totalDiscounts = MoneyHelper.readMoney(shift['total_discounts']);
  final transactionCount = (shift['transaction_count'] as num?)?.toInt() ?? 0;
  final expectedAmount =
      openingAmount + totalSales - totalReturns - totalDiscounts;

  final closingAmountController = TextEditingController();
  final notesController = TextEditingController();

  await showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    builder: (ctx) => Directionality(
      textDirection: TextDirection.rtl,
      child: Padding(
        padding: EdgeInsets.only(
          left: 20,
          right: 20,
          top: 20,
          bottom: MediaQuery.of(ctx).viewInsets.bottom +
              MediaQuery.of(ctx).viewPadding.bottom +
              20,
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    color: AppColors.divider,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: AppColors.error.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(Icons.logout,
                        color: AppColors.error, size: 24),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    'تقرير Z – إغلاق الوردية',
                    style: context.textTheme.titleLarge
                        ?.copyWith(fontWeight: FontWeight.w800),
                  ),
                ],
              ),
              const SizedBox(height: 20),

              reportRow(context, 'رقم الوردية',
                  shift['shift_number']?.toString() ?? '-'),
              reportRow(context, 'الكاشير', vm.cashierName),
              reportRow(context, 'الصندوق', vm.shiftCashBoxName),
              reportRow(context, 'المدة', vm.formattedShiftDuration),
              const Divider(height: 20),

              reportRow(context, 'رصيد الافتتاح',
                  CurrencyFormatter.format(openingAmount)),
              reportRow(context, 'إجمالي المبيعات',
                  CurrencyFormatter.format(totalSales),
                  valueColor: AppColors.success),
              reportRow(context, 'إجمالي المرتجعات',
                  CurrencyFormatter.format(totalReturns),
                  valueColor: AppColors.error),
              reportRow(context, 'إجمالي الخصومات',
                  CurrencyFormatter.format(totalDiscounts),
                  valueColor: AppColors.warning),
              reportRow(context, 'عدد المعاملات', transactionCount.toString()),
              const Divider(height: 20),

              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.06),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                      color: AppColors.primary.withValues(alpha: 0.2)),
                ),
                child: reportRow(context, 'المتوقع في الصندوق',
                    CurrencyFormatter.format(expectedAmount),
                    valueColor: AppColors.primary, isBold: true),
              ),
              const SizedBox(height: 16),

              Text('المبلغ الفعلي في الصندوق',
                  style: context.textTheme.bodyMedium
                      ?.copyWith(fontWeight: FontWeight.w600)),
              const SizedBox(height: 6),
              TextField(
                controller: closingAmountController,
                keyboardType: TextInputType.number,
                autofocus: true,
                decoration: InputDecoration(
                  hintText: 'أدخل المبلغ الفعلي',
                  suffixText: CurrencyConstants.currencySymbol(vm.selectedCurrency),
                  prefixIcon:
                      const Icon(Icons.account_balance_wallet, size: 20),
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10)),
                ),
              ),
              const SizedBox(height: 16),

              Text('ملاحظات (اختياري)',
                  style: context.textTheme.bodyMedium
                      ?.copyWith(fontWeight: FontWeight.w600)),
              const SizedBox(height: 6),
              TextField(
                controller: notesController,
                maxLines: 2,
                decoration: InputDecoration(
                  hintText: 'ملاحظات الإغلاق...',
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10)),
                ),
              ),
              const SizedBox(height: 20),

              // ── Close shift button ────────────────────────────
              SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton(
                  onPressed: () async {
                    final closingAmount =
                        double.tryParse(closingAmountController.text) ??
                            expectedAmount;
                    final difference = closingAmount - expectedAmount;
                    final now = DateTime.now();

                    // ── Step 1: Post all shift invoices (deferred posting) ──
                    await locator<ShiftService>().postShiftInvoices(shiftId);
                    final closeData = {
                      'closing_amount': closingAmount,
                      'expected_amount': expectedAmount,
                      'difference': difference,
                      'status': 'closed',
                      'closed_at': now.toIso8601String(),
                      'notes': notesController.text.isEmpty
                          ? shift['notes']
                          : notesController.text,
                      'updated_at': now.toIso8601String(),
                    };
                    await vm.closeShift(shiftId, closeData);

                    if (!context.mounted) return;
                    Navigator.pop(ctx);

                    // Show result dialog
                    showDialog(
                      context: context,
                      builder: (dctx) => Directionality(
                        textDirection: TextDirection.rtl,
                        child: AlertDialog(
                          title: Row(
                            children: [
                              Icon(
                                difference.abs() < 0.005
                                    ? Icons.check_circle
                                    : Icons.warning,
                                color: difference.abs() < 0.005
                                    ? AppColors.success
                                    : AppColors.warning,
                                size: 28,
                              ),
                              const SizedBox(width: 8),
                              const Text('تم إغلاق الوردية'),
                            ],
                          ),
                          content: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                  'المتوقع: ${CurrencyFormatter.format(expectedAmount)}'),
                              Text(
                                  'الفعلي: ${CurrencyFormatter.format(closingAmount)}'),
                              const SizedBox(height: 8),
                              if (difference.abs() >= 0.005)
                                Text(
                                  difference > 0
                                      ? 'فائض: ${CurrencyFormatter.format(difference)}'
                                      : 'عجز: ${CurrencyFormatter.format(difference.abs())}',
                                  style: TextStyle(
                                    fontWeight: FontWeight.w700,
                                    color: difference > 0
                                        ? AppColors.success
                                        : AppColors.error,
                                  ),
                                )
                              else
                                const Text(
                                  'الصندوق متوازن',
                                  style: TextStyle(
                                      fontWeight: FontWeight.w700,
                                      color: AppColors.success),
                                ),
                              const SizedBox(height: 8),
                              const Text(
                                'تم ترحيل جميع فواتير الوردية إلى الحسابات',
                                style: TextStyle(
                                    fontSize: 12, color: AppColors.info),
                              ),
                            ],
                          ),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.pop(dctx),
                              child: const Text('حسناً'),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.error,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14)),
                  ),
                  child: const Text('إغلاق الوردية وترحيل الفواتير',
                      style:
                          TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );

  closingAmountController.dispose();
  notesController.dispose();
}
