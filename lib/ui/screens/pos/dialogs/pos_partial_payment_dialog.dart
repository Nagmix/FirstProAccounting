import 'package:flutter/material.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/utils/currency_formatter.dart';
import '../../../core/viewmodels/pos_viewmodel.dart';
import '../pos_models.dart';

/// Shows the add partial payment dialog.
Future<void> showAddPartialPaymentDialog(BuildContext context, PosViewModel vm) async {
  final amountController = TextEditingController();
  String selectedMethod = vm.activePaymentMethod;

  await showDialog(
    context: context,
    builder: (ctx) => Directionality(
      textDirection: TextDirection.rtl,
      child: AlertDialog(
        title: const Text('إضافة دفعة جزئية'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            DropdownButtonFormField<String>(
              value: selectedMethod,
              decoration: const InputDecoration(labelText: 'طريقة الدفع'),
              items: [
                DropdownMenuItem(value: 'cash', child: Text('نقدي - المتبقي: ${CurrencyFormatter.format(vm.remaining)}')),
                DropdownMenuItem(value: 'card', child: const Text('بطاقة')),
                DropdownMenuItem(value: 'ewallet', child: const Text('محفظة إلكترونية')),
                DropdownMenuItem(value: 'bank_transfer', child: const Text('تحويل بنكي')),
                DropdownMenuItem(value: 'credit', child: const Text('آجل')),
              ],
              onChanged: (v) => selectedMethod = v ?? 'cash',
            ),
            const SizedBox(height: 12),
            TextField(
              controller: amountController,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                labelText: 'مبلغ الدفعة',
                suffixText: AppConstants.currency,
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
            onPressed: () {
              final amount = double.tryParse(amountController.text) ?? 0.0;
              if (amount > 0) {
                vm.addPayment(PaymentEntry(method: selectedMethod, amount: amount));
              }
              Navigator.pop(ctx);
            },
            child: const Text('إضافة'),
          ),
        ],
      ),
    ),
  );
}
