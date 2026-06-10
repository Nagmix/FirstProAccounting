import 'package:flutter/material.dart';

import 'package:firstpro/core/theme/app_colors.dart';
import 'package:firstpro/core/utils/currency_formatter.dart';
import 'package:firstpro/core/extensions/context_extensions.dart';
import 'package:firstpro/ui/screens/pos/pos_models.dart';

/// Totals section widget for the POS cart showing subtotal, discount, tax, and total.
class PosTotalsSection extends StatelessWidget {
  const PosTotalsSection({
    super.key,
    required this.subtotal,
    required this.discount,
    required this.discountType,
    required this.orderDiscount,
    required this.tax,
    required this.total,
    required this.vatRate,
  });

  final double subtotal;
  final double discount; // effective discount amount
  final DiscountType discountType;
  final double orderDiscount; // raw discount value (amount or percentage)
  final double tax;
  final double total;
  final double vatRate;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
      child: Column(
        children: [
          _totalRow(
              context, 'المجموع الفرعي', CurrencyFormatter.format(subtotal)),
          if (discount > 0) ...[
            const SizedBox(height: 3),
            _totalRow(
              context,
              'الخصم${discountType == DiscountType.percentage ? ' (${orderDiscount.toStringAsFixed(0)}%)' : ''}',
              '- ${CurrencyFormatter.format(discount)}',
              valueColor: AppColors.error,
            ),
          ],
          if (tax > 0) ...[
            const SizedBox(height: 3),
            _totalRow(
              context,
              'الضريبة (${vatRate.toStringAsFixed(0)}%)',
              CurrencyFormatter.format(tax),
            ),
          ],
          const Divider(height: 12),
          _totalRow(
            context,
            'الإجمالي',
            CurrencyFormatter.format(total),
            valueStyle: context.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.w800,
              color: AppColors.primary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _totalRow(BuildContext context, String label, String value,
      {Color? valueColor, TextStyle? valueStyle}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: context.textTheme.bodyMedium),
        Text(
          value,
          style: valueStyle ??
              context.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w600,
                color: valueColor,
              ),
        ),
      ],
    );
  }
}
