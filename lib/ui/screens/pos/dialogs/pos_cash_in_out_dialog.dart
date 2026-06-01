import 'package:flutter/material.dart';

import '../../../../core/constants/app_constants.dart';
import '../../../../core/extensions/context_extensions.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/utils/currency_formatter.dart';
import '../../../../core/di/service_locator.dart';
import '../../../../core/viewmodels/pos_viewmodel.dart';
import '../../../../data/datasources/services/shift_service.dart';

/// Opens the Cash In / Cash Out bottom sheet dialog.
Future<void> showCashInOutDialog(BuildContext context, PosViewModel vm, bool isCashIn) async {
  if (vm.activeShift == null) {
    context.showErrorSnackBar('يجب فتح وردية أولاً');
    return;
  }

  final amountController = TextEditingController();
  final reasonController = TextEditingController();

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
          bottom: MediaQuery.of(ctx).viewInsets.bottom + MediaQuery.of(ctx).viewPadding.bottom + 20,
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
                    color: (isCashIn ? AppColors.success : AppColors.error).withOpacity(0.12),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    isCashIn ? Icons.arrow_downward : Icons.arrow_upward,
                    color: isCashIn ? AppColors.success : AppColors.error,
                    size: 24,
                  ),
                ),
                const SizedBox(width: 12),
                Text(
                  isCashIn ? 'إيداع نقدي' : 'سحب نقدي',
                  style: context.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
                ),
              ],
            ),
            const SizedBox(height: 20),
            Text('المبلغ', style: context.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
            const SizedBox(height: 6),
            TextField(
              controller: amountController,
              keyboardType: TextInputType.number,
              autofocus: true,
              decoration: InputDecoration(
                hintText: isCashIn ? 'أدخل مبلغ الإيداع' : 'أدخل مبلغ السحب',
                suffixText: AppConstants.currency,
                prefixIcon: Icon(
                  Icons.payments,
                  size: 20,
                  color: isCashIn ? AppColors.success : AppColors.error,
                ),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
              ),
            ),
            const SizedBox(height: 16),
            Text('السبب', style: context.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
            const SizedBox(height: 6),
            TextField(
              controller: reasonController,
              maxLines: 2,
              decoration: InputDecoration(
                hintText: isCashIn ? 'سبب الإيداع...' : 'سبب السحب...',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
              ),
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              height: 52,
              child: ElevatedButton(
                onPressed: () async {
                  final amount = double.tryParse(amountController.text) ?? 0.0;
                  if (amount <= 0) {
                    ScaffoldMessenger.of(ctx).showSnackBar(
                      const SnackBar(content: Text('أدخل مبلغاً صحيحاً'), backgroundColor: AppColors.warning),
                    );
                    return;
                  }

                  // Record the cash in/out transaction in the database
                  try {
                    final shiftId = vm.activeShift!['id'] as int;
                    final cashBoxId = vm.activeShift!['cash_box_id'] as int;
                    final reason = reasonController.text.trim().isNotEmpty
                        ? reasonController.text.trim()
                        : (isCashIn ? 'إيداع نقدي في الوردية' : 'سحب نقدي من الوردية');

                    await locator<ShiftService>().recordCashInOut(
                      shiftId: shiftId,
                      cashBoxId: cashBoxId,
                      amount: amount,
                      isCashIn: isCashIn,
                      reason: reason,
                      currency: vm.selectedCurrency,
                    );

                    await vm.loadData();

                    if (!context.mounted) return;
                    Navigator.pop(ctx);
                    context.showSuccessSnackBar(
                      isCashIn
                          ? 'تم الإيداع بنجاح: ${CurrencyFormatter.format(amount)}'
                          : 'تم السحب بنجاح: ${CurrencyFormatter.format(amount)}',
                    );
                  } catch (e) {
                    if (context.mounted) {
                      context.showErrorSnackBar('حدث خطأ أثناء تسجيل العملية');
                    }
                  }
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: isCashIn ? AppColors.success : AppColors.error,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
                child: Text(
                  isCashIn ? 'تأكيد الإيداع' : 'تأكيد السحب',
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
