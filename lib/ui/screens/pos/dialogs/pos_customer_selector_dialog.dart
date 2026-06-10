import 'package:flutter/material.dart';

import '../../../../core/extensions/context_extensions.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/utils/currency_formatter.dart';
import '../../../../core/utils/money_helper.dart';
import '../../../../core/di/service_locator.dart';
import '../../../../core/viewmodels/pos_viewmodel.dart';
import '../../../../data/datasources/repositories/customer_repository.dart';

/// Shows the customer selector bottom sheet dialog.
Future<void> showCustomerSelectorDialog(BuildContext context, PosViewModel vm) async {
  final customers = await locator<CustomerRepository>().getAllCustomers();
  if (!context.mounted) return;
  final searchController = TextEditingController();

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
            Text('اختر العميل',
                style: context.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
            const SizedBox(height: 12),
            TextField(
              controller: searchController,
              decoration: InputDecoration(
                hintText: 'بحث عن عميل...',
                prefixIcon: const Icon(Icons.search, size: 20),
                filled: true,
                isDense: true,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              height: 280,
              child: StatefulBuilder(
                builder: (ctx, setModalState) {
                  var filtered = customers;
                  if (searchController.text.isNotEmpty) {
                    final q = searchController.text.toLowerCase();
                    filtered = customers
                        .where((c) =>
                            (c['name']?.toString() ?? '').toLowerCase().contains(q) ||
                            (c['phone']?.toString() ?? '').contains(q))
                        .toList();
                  }
                  if (filtered.isEmpty) {
                    return Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.person, size: 48, color: AppColors.textHint),
                          const SizedBox(height: 8),
                          Text('لا يوجد عملاء', style: context.textTheme.bodyLarge),
                        ],
                      ),
                    );
                  }
                  return ListView.separated(
                    shrinkWrap: true,
                    itemCount: filtered.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (context, index) {
                      final c = filtered[index];
                      final cId = c['id'] as int;
                      final cName = c['name']?.toString() ?? '';
                      final cPhone = c['phone']?.toString() ?? '';
                      final cBalance = MoneyHelper.readMoney(c['balance']);
                      final isSelected = vm.selectedCustomerId == cId;
                      return ListTile(
                        leading: CircleAvatar(
                          backgroundColor: isSelected
                              ? AppColors.primary.withValues(alpha: 0.15)
                              : AppColors.surfaceVariant,
                          child: Icon(
                            isSelected ? Icons.check : Icons.person,
                            size: 20,
                            color: isSelected ? AppColors.primary : null,
                          ),
                        ),
                        title: Text(cName, style: const TextStyle(fontWeight: FontWeight.w600)),
                        subtitle: cPhone.isNotEmpty ? Text(cPhone) : null,
                        trailing: Text(
                          CurrencyFormatter.format(cBalance),
                          style: TextStyle(
                            fontSize: 12,
                            color: cBalance > 0 ? AppColors.error : AppColors.success,
                          ),
                        ),
                        selected: isSelected,
                        onTap: () {
                          vm.setSelectedCustomer(cId, cName);
                          Navigator.pop(ctx);
                        },
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    ),
  );

  searchController.dispose();
}
