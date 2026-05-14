import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/utils/currency_formatter.dart';
import '../../../data/models/invoice_item_model.dart';

/// A reusable card widget that displays a single [InvoiceItem] inside
/// the invoice creation screen. Supports inline quantity editing and
/// swipe-to-delete.
class InvoiceItemCard extends StatelessWidget {
  const InvoiceItemCard({
    super.key,
    required this.item,
    this.onQuantityChanged,
    this.onDelete,
    this.onTap,
  });

  final InvoiceItem item;
  final ValueChanged<double>? onQuantityChanged;
  final VoidCallback? onDelete;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Dismissible(
      key: ValueKey(item.productId),
      direction: DismissDirection.startToEnd,
      onDismissed: onDelete != null ? (_) => onDelete!() : null,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 24),
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        decoration: BoxDecoration(
          color: AppColors.error,
          borderRadius: BorderRadius.circular(16),
        ),
        child: const Icon(Icons.delete_outline, color: Colors.white, size: 28),
      ),
      child: Card(
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(14),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              children: [
                // ── Product icon ──────────────────────────────────
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(
                    Icons.inventory_2_outlined,
                    color: AppColors.primary,
                    size: 22,
                  ),
                ),
                const SizedBox(width: 12),

                // ── Name & price ──────────────────────────────────
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        item.productName,
                        style: theme.textTheme.bodyLarge?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${CurrencyFormatter.formatValue(item.unitPrice)} × ${item.quantity.toStringAsFixed(item.quantity == item.quantity.truncate() ? 0 : 3)}',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: isDark
                              ? AppColors.darkTextSecondary
                              : AppColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),

                // ── Quantity stepper ───────────────────────────────
                if (onQuantityChanged != null) ...[
                  _QuantityStepper(
                    quantity: item.quantity,
                    onChanged: onQuantityChanged!,
                  ),
                  const SizedBox(width: 12),
                ],

                // ── Total ─────────────────────────────────────────
                Text(
                  CurrencyFormatter.format(item.totalPrice),
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: AppColors.primary,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
//  QUANTITY STEPPER (inline +/-)
// ═══════════════════════════════════════════════════════════════════════════
class _QuantityStepper extends StatelessWidget {
  const _QuantityStepper({
    required this.quantity,
    required this.onChanged,
  });

  final double quantity;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      decoration: BoxDecoration(
        color: AppColors.surfaceVariant.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _stepButton(
            icon: Icons.remove,
            onTap: () => onChanged((quantity - 1).clamp(0.001, 99999)),
          ),
          Container(
            constraints: const BoxConstraints(minWidth: 36),
            alignment: Alignment.center,
            child: Text(
              quantity.toStringAsFixed(quantity == quantity.truncate() ? 0 : 3),
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          _stepButton(
            icon: Icons.add,
            onTap: () => onChanged((quantity + 1).clamp(0.001, 99999)),
          ),
        ],
      ),
    );
  }

  Widget _stepButton({required IconData icon, required VoidCallback onTap}) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.all(6),
        child: Icon(icon, size: 18, color: AppColors.primary),
      ),
    );
  }
}
