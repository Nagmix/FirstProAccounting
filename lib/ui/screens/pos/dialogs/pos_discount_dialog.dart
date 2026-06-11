import 'package:flutter/material.dart';

import 'package:firstpro/core/constants/app_constants.dart';
import 'package:firstpro/core/extensions/context_extensions.dart';
import 'package:firstpro/core/helpers/currency_constants.dart';
import 'package:firstpro/core/theme/app_colors.dart';
import 'package:firstpro/core/viewmodels/pos_viewmodel.dart';
import 'package:firstpro/ui/screens/pos/pos_models.dart';

/// Shows the discount dialog.
void showDiscountDialog(BuildContext context, PosViewModel vm) {
  if (vm.activeShift == null) {
    context.showErrorSnackBar('يجب فتح وردية أولاً');
    return;
  }
  final controller = TextEditingController(
    text: vm.orderDiscount > 0 ? vm.orderDiscount.toStringAsFixed(2) : '',
  );
  showDialog(
    context: context,
    builder: (ctx) => Directionality(
      textDirection: TextDirection.rtl,
      child: AlertDialog(
        title: const Text('خصم على الطلب'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: controller,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                labelText: vm.discountType == DiscountType.percentage
                    ? 'نسبة الخصم %'
                    : 'مبلغ الخصم',
                suffixText: vm.discountType == DiscountType.percentage
                    ? '%'
                    : CurrencyConstants.currencySymbol(vm.selectedCurrency),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                const Text('نوع الخصم: '),
                const SizedBox(width: 8),
                ChoiceChip(
                  label: const Text('مبلغ ثابت'),
                  selected: vm.discountType == DiscountType.fixed,
                  onSelected: (_) =>
                      vm.setOrderDiscount(vm.orderDiscount, DiscountType.fixed),
                ),
                const SizedBox(width: 6),
                ChoiceChip(
                  label: const Text('نسبة مئوية'),
                  selected: vm.discountType == DiscountType.percentage,
                  onSelected: (_) => vm.setOrderDiscount(
                      vm.orderDiscount, DiscountType.percentage),
                ),
              ],
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              vm.setOrderDiscount(0, DiscountType.fixed);
              Navigator.pop(ctx);
            },
            child: const Text('إزالة الخصم'),
          ),
          ElevatedButton(
            onPressed: () {
              final value = double.tryParse(controller.text) ?? 0;
              // Validation: discount must be >= 0
              if (value < 0) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                      content: Text('الخصم لا يمكن أن يكون سالباً'),
                      backgroundColor: AppColors.error),
                );
                return;
              }
              // Validation: fixed discount must not exceed total
              if (vm.discountType == DiscountType.fixed &&
                  value > vm.subtotal) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                      content: Text('الخصم لا يمكن أن يتجاوز الإجمالي'),
                      backgroundColor: AppColors.error),
                );
                return;
              }
              // Validation: percentage discount must not exceed 100%
              if (vm.discountType == DiscountType.percentage && value > 100) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                      content: Text('نسبة الخصم لا يمكن أن تتجاوز 100%'),
                      backgroundColor: AppColors.error),
                );
                return;
              }
              vm.setOrderDiscount(value, vm.discountType);
              Navigator.pop(ctx);
            },
            child: const Text('تطبيق'),
          ),
        ],
      ),
    ),
  );

  controller.dispose();
}
