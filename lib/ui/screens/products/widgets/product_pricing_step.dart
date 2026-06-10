import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:firstpro/core/constants/app_constants.dart';
import 'package:firstpro/core/theme/app_colors.dart';
import 'package:firstpro/ui/screens/products/widgets/product_form_helpers.dart';

// ═══════════════════════════════════════════════════════════════════
//  Step 3 – الأسعار
// ═══════════════════════════════════════════════════════════════════

class ProductPricingStep extends StatelessWidget {
  // Controllers
  final TextEditingController costPriceController;
  final TextEditingController sellPriceController;
  final TextEditingController specialWholesalePriceController;
  final TextEditingController minimumSalePriceController;
  final TextEditingController taxRateController;

  // Values
  final bool hasMultiUnits;
  final int saleUnitSource; // 0 = base, 1 = purchase
  final double purchaseUnitFactor;
  final int? selectedPurchaseUnitId;
  final int? selectedBaseUnitId;
  final int? effectiveSaleUnitId;
  final bool taxInclusive;

  // Helpers
  final String Function(int? id) unitNameById;

  // Callbacks
  final VoidCallback onStateChanged;
  final ValueChanged<bool> onTaxInclusiveChanged;

  const ProductPricingStep({
    super.key,
    required this.costPriceController,
    required this.sellPriceController,
    required this.specialWholesalePriceController,
    required this.minimumSalePriceController,
    required this.taxRateController,
    required this.hasMultiUnits,
    required this.saleUnitSource,
    required this.purchaseUnitFactor,
    required this.selectedPurchaseUnitId,
    required this.selectedBaseUnitId,
    required this.effectiveSaleUnitId,
    required this.taxInclusive,
    required this.unitNameById,
    required this.onStateChanged,
    required this.onTaxInclusiveChanged,
  });

  @override
  Widget build(BuildContext context) {
    final hasMulti = hasMultiUnits;
    final purchaseUnitName = unitNameById(selectedPurchaseUnitId);
    final baseUnitName = unitNameById(selectedBaseUnitId);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const StepTitle(title: 'الأسعار', icon: Icons.label),

        // سعر التكلفة + سعر البيع
        Row(
          children: [
            Expanded(
              child: ProductPriceField(
                controller: costPriceController,
                label: hasMulti
                    ? 'سعر تكلفة الـ $purchaseUnitName *'
                    : 'سعر التكلفة *',
                onChanged: hasMulti ? (_) => onStateChanged() : null,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: ProductPriceField(
                controller: sellPriceController,
                label: hasMulti
                    ? 'سعر بيع الـ ${unitNameById(effectiveSaleUnitId)} *'
                    : 'سعر بيع الـ $baseUnitName *',
                onChanged: hasMulti ? (_) => onStateChanged() : null,
              ),
            ),
          ],
        ),

        // Auto-calculated base unit cost display
        if (hasMulti && costPriceController.text.isNotEmpty) ...[
          const SizedBox(height: 4),
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Text(
              '↪ سعر تكلفة الـ $baseUnitName = ${_calculateBaseCostFromCostField()}',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: AppColors.success,
                    fontWeight: FontWeight.w600,
                  ),
            ),
          ),
        ],
        // Auto-calculated base unit sell price display
        if (hasMulti &&
            saleUnitSource == 1 &&
            sellPriceController.text.isNotEmpty) ...[
          const SizedBox(height: 2),
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Text(
              '↪ سعر بيع الـ $baseUnitName = ${_calculateBaseSellPrice()}',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: AppColors.info,
                    fontWeight: FontWeight.w600,
                  ),
            ),
          ),
        ],
        const SizedBox(height: 14),

        // أقل سعر بيع (سعر الجملة الخاصة)
        ProductPriceField(
          controller: specialWholesalePriceController,
          label: hasMulti
              ? 'سعر الجملة الخاصة للـ ${unitNameById(effectiveSaleUnitId)}'
              : 'سعر الجملة الخاصة',
        ),
        const SizedBox(height: 14),

        // سعر البيع الأدنى
        ProductPriceField(
          controller: minimumSalePriceController,
          label: hasMulti
              ? 'سعر البيع الأدنى للـ ${unitNameById(effectiveSaleUnitId)}'
              : 'سعر البيع الأدنى',
        ),
        const SizedBox(height: 14),

        // الضريبة
        Row(
          children: [
            Expanded(
              child: TextFormField(
                controller: taxRateController,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                textInputAction: TextInputAction.next,
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d{0,2}')),
                ],
                decoration: const InputDecoration(
                  isDense: true,
                  labelText: 'الضريبة %',
                  suffixText: '%',
                  prefixIcon: Icon(Icons.receipt),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: ProductSwitchTile(
                title: 'شامل الضريبة',
                subtitle: taxInclusive ? 'نعم' : 'لا',
                value: taxInclusive,
                onChanged: onTaxInclusiveChanged,
              ),
            ),
          ],
        ),
        const SizedBox(height: 40),
      ],
    );
  }

  /// Display string for auto-calculated base unit cost from the cost price field
  String _calculateBaseCostFromCostField() {
    final costPrice = double.tryParse(costPriceController.text);
    if (costPrice == null || costPrice <= 0) return '...';
    final factor = purchaseUnitFactor;
    if (factor <= 1) {
      return '${costPrice.toStringAsFixed(2)} ${AppConstants.currency}';
    }
    final baseCost = costPrice / factor;
    return '${baseCost.toStringAsFixed(2)} ${AppConstants.currency}';
  }

  /// Display string for auto-calculated base unit sell price
  String _calculateBaseSellPrice() {
    final sellPrice = double.tryParse(sellPriceController.text);
    if (sellPrice == null || sellPrice <= 0) return '...';
    final factor = purchaseUnitFactor;
    if (factor <= 1) {
      return '${sellPrice.toStringAsFixed(2)} ${AppConstants.currency}';
    }
    final baseSell = sellPrice / factor;
    return '${baseSell.toStringAsFixed(2)} ${AppConstants.currency}';
  }
}
