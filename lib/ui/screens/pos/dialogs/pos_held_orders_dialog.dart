import 'package:flutter/material.dart';

import '../../../../core/extensions/context_extensions.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/utils/currency_formatter.dart';
import '../../../../core/viewmodels/pos_viewmodel.dart';

/// Shows the held orders bottom sheet dialog.
/// [onRestore] is called after an order is restored (e.g., to animate the cart sheet).
void showHeldOrdersDialog(BuildContext context, PosViewModel vm, VoidCallback onRestore) {
  if (vm.heldOrders.isEmpty) {
    context.showSnackBar('لا توجد طلبات معلقة');
    return;
  }

  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    builder: (ctx) => Directionality(
      textDirection: TextDirection.rtl,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('الطلبات المعلقة', style: context.textTheme.titleLarge),
            const SizedBox(height: 12),
            ...vm.heldOrders.asMap().entries.map((entry) {
              final idx = entry.key;
              final order = entry.value;
              final total = order.items.fold(0.0, (s, i) => s + i.total);
              return ListTile(
                leading: CircleAvatar(
                  backgroundColor: AppColors.secondary.withOpacity(0.15),
                  child: Text('${idx + 1}'),
                ),
                title: Text(
                  '${order.items.length} صنف – ${CurrencyFormatter.format(total)}',
                ),
                subtitle: Text(
                  order.customerName.isNotEmpty ? 'العميل: ${order.customerName}' : 'بدون عميل',
                ),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      onPressed: () {
                        vm.restoreHeldOrder(idx);
                        Navigator.pop(ctx);
                        onRestore();
                      },
                      icon: const Icon(Icons.refresh,
                          color: AppColors.primary),
                      tooltip: 'استرجاع',
                    ),
                    IconButton(
                      onPressed: () {
                        vm.deleteHeldOrder(idx);
                        Navigator.pop(ctx);
                      },
                      icon: const Icon(Icons.delete, color: AppColors.error),
                      tooltip: 'حذف',
                    ),
                  ],
                ),
              );
            }),
          ],
        ),
      ),
    ),
  );
}
