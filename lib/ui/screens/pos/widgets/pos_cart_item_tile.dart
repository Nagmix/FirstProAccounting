import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/utils/currency_formatter.dart';
import '../../../../core/extensions/context_extensions.dart';

/// Cart item tile widget for displaying a single item in the POS cart.
class PosCartItemTile extends StatelessWidget {
  const PosCartItemTile({
    super.key,
    required this.name,
    required this.unitPrice,
    required this.quantity,
    required this.unitName,
    required this.total,
    required this.onIncrement,
    required this.onDecrement,
    required this.onEditQuantity,
    required this.onDelete,
  });

  final String name;
  final double unitPrice;
  final int quantity;
  final String unitName;
  final double total;

  final VoidCallback onIncrement;
  final VoidCallback onDecrement;
  final VoidCallback onEditQuantity;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 3),
      child: Card(
        margin: EdgeInsets.zero,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
          side: BorderSide(color: AppColors.border.withValues(alpha: 0.5)),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          child: Row(
            children: [
              // Product info
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${CurrencyFormatter.format(unitPrice)} × $quantity $unitName',
                      style: TextStyle(
                        fontSize: 11,
                        color: context.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),

              // Quantity controls
              Container(
                decoration: BoxDecoration(
                  color: AppColors.surfaceVariant,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _qtyButton(
                      icon: Icons.remove,
                      onTap: onDecrement,
                    ),
                    Container(
                      width: 40,
                      alignment: Alignment.center,
                      child: GestureDetector(
                        onTap: onEditQuantity,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                          decoration: BoxDecoration(
                            border: Border.all(color: AppColors.primary.withValues(alpha: 0.3)),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            '$quantity',
                            style: const TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 14,
                              color: AppColors.primary,
                            ),
                          ),
                        ),
                      ),
                    ),
                    _qtyButton(
                      icon: Icons.add,
                      onTap: onIncrement,
                    ),
                  ],
                ),
              ),

              const SizedBox(width: 8),

              // Total price
              SizedBox(
                width: 70,
                child: Text(
                  CurrencyFormatter.format(total),
                  textAlign: TextAlign.left,
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                    color: AppColors.primary,
                  ),
                ),
              ),

              // Delete
              IconButton(
                onPressed: onDelete,
                icon: const Icon(Icons.delete, size: 16, color: AppColors.error),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
                tooltip: 'حذف',
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _qtyButton({required IconData icon, required VoidCallback onTap}) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(6),
      child: Padding(
        padding: const EdgeInsets.all(4),
        child: Icon(icon, size: 14),
      ),
    );
  }
}
