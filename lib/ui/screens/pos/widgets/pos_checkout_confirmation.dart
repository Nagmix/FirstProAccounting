import 'package:flutter/material.dart';

import '../../../../core/extensions/context_extensions.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/utils/currency_formatter.dart';
import '../../../../core/viewmodels/pos_viewmodel.dart';
import '../pos_models.dart';
import '../dialogs/pos_reports_dialog.dart' show reportRow;

/// Checkout confirmation overlay widget.
/// Also shown during the saving phase with a progress indicator.
class PosCheckoutConfirmationOverlay extends StatelessWidget {
  const PosCheckoutConfirmationOverlay({
    super.key,
    required this.vm,
    required this.onConfirm,
    required this.onCancel,
  });

  final PosViewModel vm;
  final VoidCallback onConfirm;
  final VoidCallback onCancel;

  bool get _isSaving => vm.checkoutPhase == CheckoutPhase.saving;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {}, // Absorb background taps – do nothing
      behavior: HitTestBehavior.opaque,
      child: Container(
        color: Colors.black.withOpacity(0.55),
        child: Center(
          child: Card(
            margin: const EdgeInsets.symmetric(horizontal: 24),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            elevation: 12,
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      if (_isSaving)
                        const SizedBox(
                          width: 26, height: 26,
                          child: CircularProgressIndicator(strokeWidth: 3),
                        )
                      else
                        const Icon(Icons.shopping_cart_checkout, color: AppColors.primary, size: 26),
                      const SizedBox(width: 10),
                      Text(
                        _isSaving ? 'جارٍ حفظ الفاتورة...' : 'تأكيد عملية البيع',
                        style: context.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  reportRow(context, 'عدد الأصناف', '${vm.capturedCartLength}'),
                  reportRow(context, 'المجموع الفرعي', CurrencyFormatter.format(vm.capturedSubtotal)),
                  if (vm.capturedDiscount > 0)
                    reportRow(context, 'الخصم', '- ${CurrencyFormatter.format(vm.capturedDiscount)}', valueColor: AppColors.error),
                  if (vm.capturedTax > 0)
                    reportRow(context, 'الضريبة', CurrencyFormatter.format(vm.capturedTax)),
                  const Divider(height: 20),
                  reportRow(context, 'الإجمالي', CurrencyFormatter.format(vm.capturedTotal),
                      valueColor: AppColors.primary, isBold: true),
                  const SizedBox(height: 8),
                  reportRow(context, 'طريقة الدفع', vm.capturedPaymentLabel),
                  if (vm.selectedCustomerName.isNotEmpty)
                    reportRow(context, 'العميل', vm.selectedCustomerName),
                  const SizedBox(height: 6),
                  Text(
                    'سيتم تسجيل الفاتورة وترحيلها عند إغلاق الوردية',
                    style: TextStyle(fontSize: 11, color: context.textSecondary),
                  ),
                  const SizedBox(height: 20),
                  if (_isSaving)
                    const Center(child: Padding(
                      padding: EdgeInsets.symmetric(vertical: 14),
                      child: Text('يرجى الانتظار...', style: TextStyle(fontSize: 15, color: AppColors.textSecondary)),
                    ))
                  else
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: onCancel,
                            style: OutlinedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            ),
                            child: const Text('إلغاء', style: TextStyle(fontSize: 15)),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: ElevatedButton(
                            onPressed: onConfirm,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppColors.success,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            ),
                            child: const Text('تأكيد البيع', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                          ),
                        ),
                      ],
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
