import 'package:flutter/material.dart';

import 'package:firstpro/core/extensions/context_extensions.dart';
import 'package:firstpro/core/theme/app_colors.dart';
import 'package:firstpro/core/utils/currency_formatter.dart';
import 'package:firstpro/core/utils/money_helper.dart';
import 'package:firstpro/core/viewmodels/pos_viewmodel.dart';

/// Shift info bar widget displayed at the top of the POS screen when a shift is active.
class PosShiftInfoBar extends StatelessWidget {
  const PosShiftInfoBar({
    super.key,
    required this.vm,
    required this.onCashIn,
    required this.onCashOut,
  });

  final PosViewModel vm;
  final VoidCallback onCashIn;
  final VoidCallback onCashOut;

  @override
  Widget build(BuildContext context) {
    final shift = vm.activeShift!;
    final totalSales = MoneyHelper.readMoney(shift['total_sales']);
    final openingAmount = MoneyHelper.readMoney(shift['opening_amount']);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            AppColors.success.withValues(alpha: 0.06),
            AppColors.success.withValues(alpha: 0.12),
          ],
          begin: Alignment.centerRight,
          end: Alignment.centerLeft,
        ),
        border: Border(
          bottom: BorderSide(
            color: AppColors.success.withValues(alpha: 0.25),
          ),
        ),
      ),
      child: SafeArea(
        top: false,
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              // Pulsing dot
              Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                  color: AppColors.success,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.success.withValues(alpha: 0.5),
                      blurRadius: 6,
                      spreadRadius: 1,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Text(
                'وردية مفتوحة',
                style: context.textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: AppColors.success,
                ),
              ),
              const SizedBox(width: 14),

              // Cashier name
              _shiftChip(
                context,
                icon: Icons.person,
                label: 'الكاشير',
                value: vm.cashierName,
              ),
              const SizedBox(width: 10),

              // Duration
              _shiftChip(
                context,
                icon: Icons.access_time,
                label: 'المدة',
                value: vm.formattedShiftDuration,
              ),
              const SizedBox(width: 10),

              // Cash box
              _shiftChip(
                context,
                icon: Icons.account_balance_wallet,
                label: 'الصندوق',
                value: vm.shiftCashBoxName,
              ),
              const SizedBox(width: 10),

              // Total sales
              _shiftChip(
                context,
                icon: Icons.show_chart,
                label: 'المبيعات',
                value: CurrencyFormatter.format(totalSales),
              ),
              const SizedBox(width: 10),

              // Opening amount
              _shiftChip(
                context,
                icon: Icons.account_balance_wallet,
                label: 'الافتتاح',
                value: CurrencyFormatter.format(openingAmount),
              ),
              const SizedBox(width: 12),

              // Cash In/Out
              _shiftActionChip(
                label: 'إيداع',
                icon: Icons.arrow_downward,
                color: AppColors.success,
                onTap: onCashIn,
              ),
              const SizedBox(width: 6),
              _shiftActionChip(
                label: 'سحب',
                icon: Icons.arrow_upward,
                color: AppColors.error,
                onTap: onCashOut,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _shiftChip(
    BuildContext context, {
    required IconData icon,
    required String label,
    required String value,
  }) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 15, color: AppColors.primary),
        const SizedBox(width: 3),
        Text(
          '$label: ',
          style: context.textTheme.bodySmall?.copyWith(
            color: context.textSecondary,
            fontSize: 11,
          ),
        ),
        Text(
          value,
          style: context.textTheme.bodySmall?.copyWith(
            fontWeight: FontWeight.w700,
            color: context.textPrimary,
            fontSize: 11,
          ),
        ),
      ],
    );
  }

  Widget _shiftActionChip({
    required String label,
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          border: Border.all(color: color.withValues(alpha: 0.4)),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 13, color: color),
            const SizedBox(width: 3),
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
