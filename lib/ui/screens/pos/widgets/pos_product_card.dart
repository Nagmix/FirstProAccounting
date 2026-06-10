import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/utils/currency_formatter.dart';
import '../../../../core/extensions/context_extensions.dart';
import '../../../../data/models/product_model.dart';

/// Product card widget for the POS product grid.
class PosProductCard extends StatelessWidget {
  const PosProductCard({
    super.key,
    required this.product,
    required this.onTap,
  });

  final Product product;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final lowStock =
        product.currentStock <= product.minStock && product.currentStock > 0;
    final outOfStock = product.currentStock <= 0 && !product.allowNegative;

    return Card(
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(8),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Product icon
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(
                  Icons.inventory_2,
                  color: AppColors.primary,
                  size: 20,
                ),
              ),
              const SizedBox(height: 6),

              // Name
              Text(
                product.nameAr,
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: context.textTheme.bodySmall
                    ?.copyWith(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 3),

              // Price
              Text(
                CurrencyFormatter.format(product.sellPrice),
                style: context.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: AppColors.primary,
                ),
              ),
              const SizedBox(height: 3),

              // Stock badge
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                decoration: BoxDecoration(
                  color: outOfStock
                      ? AppColors.errorLight
                      : lowStock
                          ? AppColors.warningLight
                          : product.currentStock <= 0
                              ? AppColors.warningLight
                              : AppColors.successLight,
                  borderRadius: BorderRadius.circular(5),
                ),
                child: Text(
                  outOfStock
                      ? 'نفذ'
                      : product.currentStock <= 0
                          ? 'مسموح'
                          : lowStock
                              ? 'منخفض'
                              : '${product.currentStock.toStringAsFixed(0)}',
                  style: TextStyle(
                    fontSize: 8,
                    fontWeight: FontWeight.w600,
                    color: outOfStock
                        ? AppColors.error
                        : lowStock || product.currentStock <= 0
                            ? AppColors.warning
                            : AppColors.success,
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
