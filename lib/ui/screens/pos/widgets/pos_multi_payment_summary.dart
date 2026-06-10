import 'package:flutter/material.dart';

import 'package:firstpro/core/extensions/context_extensions.dart';
import 'package:firstpro/core/theme/app_colors.dart';
import 'package:firstpro/core/utils/currency_formatter.dart';
import 'package:firstpro/core/viewmodels/pos_viewmodel.dart';

/// Multi-payment summary widget for the POS cart.
class PosMultiPaymentSummary extends StatelessWidget {
  const PosMultiPaymentSummary({
    super.key,
    required this.vm,
    required this.onRemovePayment,
    required this.paymentLabel,
  });

  final PosViewModel vm;
  final VoidCallback onRemovePayment;
  final String Function(String method) paymentLabel;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: AppColors.primary.withValues(alpha: 0.04),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: AppColors.primary.withValues(alpha: 0.15)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.credit_card,
                    size: 16, color: AppColors.primary),
                const SizedBox(width: 6),
                Text(
                  'المدفوعات',
                  style: context.textTheme.bodySmall?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: AppColors.primary,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            ...vm.payments.map((p) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          Icon(
                            p.method == 'cash'
                                ? Icons.payments
                                : p.method == 'credit'
                                    ? Icons.access_time
                                    : p.method == 'card'
                                        ? Icons.credit_card
                                        : p.method == 'ewallet'
                                            ? Icons.account_balance_wallet
                                            : Icons.business,
                            size: 14,
                            color: AppColors.primary,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            paymentLabel(p.method),
                            style: const TextStyle(fontSize: 12),
                          ),
                          if (p.providerName != null &&
                              p.providerName!.isNotEmpty) ...[
                            Text(
                              ' (${p.providerName})',
                              style: TextStyle(
                                  fontSize: 11, color: context.textSecondary),
                            ),
                          ],
                        ],
                      ),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            CurrencyFormatter.format(p.amount),
                            style: const TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 12,
                            ),
                          ),
                          const SizedBox(width: 4),
                          InkWell(
                            onTap: () =>
                                vm.removePayment(vm.payments.indexOf(p)),
                            child: const Icon(
                              Icons.close,
                              size: 14,
                              color: AppColors.error,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                )),
            if (vm.remaining.abs() > 0.01) ...[
              const Divider(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    vm.remaining > 0 ? 'المتبقي' : 'الزيادة',
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 12,
                      color: vm.remaining > 0
                          ? AppColors.error
                          : AppColors.success,
                    ),
                  ),
                  Text(
                    CurrencyFormatter.format(vm.remaining.abs()),
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 12,
                      color: vm.remaining > 0
                          ? AppColors.error
                          : AppColors.success,
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}
