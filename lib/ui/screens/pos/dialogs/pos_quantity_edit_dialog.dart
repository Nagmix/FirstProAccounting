import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:firstpro/core/viewmodels/pos_viewmodel.dart';

/// Shows the edit quantity dialog for a cart item.
Future<void> showEditQuantityDialog(
    BuildContext context, PosViewModel vm, int index) async {
  final controller =
      TextEditingController(text: '${vm.cartItems[index].quantity}');
  final result = await showDialog<int>(
    context: context,
    builder: (ctx) => Directionality(
      textDirection: TextDirection.rtl,
      child: AlertDialog(
        title: Text('الكمية - ${vm.cartItems[index].name}'),
        content: TextField(
          controller: controller,
          autofocus: true,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          inputFormatters: [
            FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d*$')),
          ],
          decoration: const InputDecoration(
            labelText: 'الكمية',
            prefixIcon: Icon(Icons.format_list_numbered),
          ),
          onSubmitted: (v) {
            final qty = double.tryParse(v)?.round();
            Navigator.pop(ctx, qty);
          },
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('إلغاء'),
          ),
          ElevatedButton(
            onPressed: () {
              final qty = double.tryParse(controller.text)?.round();
              Navigator.pop(ctx, qty);
            },
            child: const Text('تأكيد'),
          ),
        ],
      ),
    ),
  );
  controller.dispose();

  if (result != null && result > 0) {
    vm.updateCartQuantity(index, result);
  }
}
