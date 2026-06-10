import 'package:flutter/material.dart';

import '../../../../core/extensions/context_extensions.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/utils/currency_formatter.dart';
import '../../../../core/viewmodels/pos_viewmodel.dart';

/// Checkout completed overlay widget.
class PosCheckoutCompletedOverlay extends StatelessWidget {
  const PosCheckoutCompletedOverlay({
    super.key,
    required this.vm,
    required this.onDismiss,
    required this.onPrint,
  });

  final PosViewModel vm;
  final VoidCallback onDismiss;
  final VoidCallback onPrint;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {}, // Absorb background taps – do nothing
      behavior: HitTestBehavior.opaque,
      child: Container(
        color: Colors.black.withValues(alpha: 0.55),
        child: Center(
          child: Card(
            margin: const EdgeInsets.symmetric(horizontal: 24),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            elevation: 12,
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.check_circle,
                          color: AppColors.success, size: 28),
                      const SizedBox(width: 10),
                      Text(
                        'تم إنهاء البيع',
                        style: context.textTheme.titleLarge
                            ?.copyWith(fontWeight: FontWeight.w800),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Text('رقم الفاتورة: ${vm.lastInvoiceId}',
                      style: const TextStyle(
                          fontSize: 14, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 4),
                  Text(
                      'الإجمالي: ${CurrencyFormatter.format(vm.capturedTotal)}',
                      style: const TextStyle(fontSize: 14)),
                  const SizedBox(height: 4),
                  Text('طريقة الدفع: ${vm.capturedPaymentLabel}',
                      style: const TextStyle(fontSize: 14)),
                  if (vm.selectedCustomerName.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text('العميل: ${vm.selectedCustomerName}',
                        style: const TextStyle(fontSize: 14)),
                  ],
                  const SizedBox(height: 10),
                  const Text(
                    'لم يتم ترحيل الفاتورة بعد – سيتم ترحيلها عند إغلاق الوردية',
                    style: TextStyle(fontSize: 11, color: AppColors.info),
                  ),
                  const SizedBox(height: 20),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: onPrint,
                          icon: const Icon(Icons.print, size: 18),
                          label: const Text('طباعه'),
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12)),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: ElevatedButton(
                          onPressed: onDismiss,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.primary,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12)),
                          ),
                          child: const Text('إغلاق',
                              style: TextStyle(
                                  fontSize: 15, fontWeight: FontWeight.w700)),
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
