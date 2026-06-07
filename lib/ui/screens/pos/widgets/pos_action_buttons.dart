import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/utils/currency_formatter.dart';
import '../pos_models.dart';

/// Action buttons section widget for the POS cart (checkout, hold, clear, etc.).
class PosActionButtons extends StatelessWidget {
  const PosActionButtons({
    super.key,
    required this.cartLength,
    required this.total,
    required this.activePaymentMethod,
    required this.paymentsLength,
    required this.remaining,
    required this.checkoutPhase,
    required this.paymentLabel,
    required this.onAddPayment,
    required this.onAddPartialPayment,
    required this.onStartCheckout,
    required this.onHoldOrder,
    required this.onClearInvoice,
  });

  final int cartLength;
  final double total;
  final String activePaymentMethod;
  final int paymentsLength;
  final double remaining;
  final CheckoutPhase checkoutPhase;

  /// Callback to get the localized payment method label.
  final String Function(String method) paymentLabel;

  final VoidCallback onAddPayment;
  final VoidCallback onAddPartialPayment;
  final VoidCallback onStartCheckout;
  final VoidCallback onHoldOrder;
  final VoidCallback onClearInvoice;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 20),
      child: Column(
        children: [
          // Add payment button
          if (cartLength > 0 && paymentsLength == 0)
            SizedBox(
              width: double.infinity,
              height: 44,
              child: OutlinedButton.icon(
                onPressed: onAddPayment,
                icon: const Icon(Icons.add, size: 18),
                label: Text('إضافة دفعة: ${paymentLabel(activePaymentMethod)}'),
                style: OutlinedButton.styleFrom(
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ),

          // Add partial payment (multi-payment)
          if (cartLength > 0 && paymentsLength > 0 && remaining > 0.01)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: SizedBox(
                width: double.infinity,
                height: 40,
                child: OutlinedButton.icon(
                  onPressed: onAddPartialPayment,
                  icon: const Icon(Icons.add_circle, size: 16),
                  label: const Text('إضافة دفعة أخرى'),
                  style: OutlinedButton.styleFrom(
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                ),
              ),
            ),

          const SizedBox(height: 8),

          // Checkout button
          SizedBox(
            width: double.infinity,
            height: 52,
            child: ElevatedButton(
              onPressed: (cartLength == 0 || checkoutPhase != CheckoutPhase.idle) ? null : onStartCheckout,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.success,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.check_circle, size: 20),
                  const SizedBox(width: 8),
                  Text(
                    'إنهاء البيع  ${CurrencyFormatter.format(total)}',
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),

          // Hold order button
          SizedBox(
            width: double.infinity,
            height: 42,
            child: OutlinedButton.icon(
              onPressed: cartLength == 0 ? null : onHoldOrder,
              icon: const Icon(Icons.pause_circle, size: 18),
              label: const Text('تعليق الطلب'),
              style: OutlinedButton.styleFrom(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),

          // Clear invoice button
          SizedBox(
            width: double.infinity,
            height: 42,
            child: OutlinedButton.icon(
              onPressed: (cartLength == 0 || checkoutPhase != CheckoutPhase.idle) ? null : onClearInvoice,
              icon: const Icon(Icons.delete_outline, size: 18),
              label: const Text('مسح الفاتورة'),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.error,
                side: const BorderSide(color: AppColors.error),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
