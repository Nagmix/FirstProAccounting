import 'package:flutter/material.dart';

import 'package:firstpro/core/theme/app_colors.dart';
import 'package:firstpro/core/extensions/context_extensions.dart';

/// Payment method selector widget for the POS cart.
class PosPaymentMethodSelector extends StatelessWidget {
  const PosPaymentMethodSelector({
    super.key,
    required this.activeMethod,
    required this.onMethodChanged,
  });

  final String activeMethod;
  final ValueChanged<String> onMethodChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'طريقة الدفع',
            style: context.textTheme.bodySmall?.copyWith(
              fontWeight: FontWeight.w600,
              color: context.textSecondary,
            ),
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              _payMethodChip(context, 'نقدي', 'cash', Icons.payments),
              const SizedBox(width: 4),
              _payMethodChip(context, 'آجل', 'credit', Icons.access_time),
              const SizedBox(width: 4),
              _payMethodChip(context, 'بطاقة', 'card', Icons.credit_card),
              const SizedBox(width: 4),
              _payMethodChip(
                  context, 'محفظة', 'ewallet', Icons.account_balance_wallet),
              const SizedBox(width: 4),
              _payMethodChip(context, 'تحويل', 'bank_transfer', Icons.business),
            ],
          ),
        ],
      ),
    );
  }

  Widget _payMethodChip(
      BuildContext context, String label, String method, IconData icon) {
    final selected = activeMethod == method;
    return Expanded(
      child: SizedBox(
        height: 36,
        child: OutlinedButton(
          onPressed: () => onMethodChanged(method),
          style: OutlinedButton.styleFrom(
            backgroundColor:
                selected ? AppColors.primary.withValues(alpha: 0.1) : null,
            side: BorderSide(
              color: selected ? AppColors.primary : AppColors.border,
              width: selected ? 2 : 1,
            ),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            padding: const EdgeInsets.symmetric(horizontal: 4),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 13, color: selected ? AppColors.primary : null),
              const SizedBox(width: 2),
              Flexible(
                child: Text(
                  label,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                    color: selected ? AppColors.primary : null,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
