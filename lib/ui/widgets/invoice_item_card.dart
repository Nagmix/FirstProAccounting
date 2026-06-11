import 'package:flutter/material.dart';

import 'package:firstpro/core/theme/app_colors.dart';
import 'package:firstpro/core/utils/currency_formatter.dart';
import 'package:firstpro/data/models/invoice_item_model.dart';

/// A reusable card widget that displays a single [InvoiceItem] inside
/// the invoice creation screen. Supports inline quantity editing and
/// swipe-to-delete.
///
/// Layout:
///   Row 1: Item name ........................  quantity × price
///   Row 2: [−] [ qty ] [+]                 total price
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

  static const Color _accentBlue = Color(0xFF4F6AF0);
  static const Color _accentPurple = Color(0xFF7C3AED);

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
        margin: const EdgeInsets.only(bottom: 8),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [AppColors.error, Color(0xFFEF4444)],
            begin: Alignment.centerRight,
            end: Alignment.centerLeft,
          ),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.delete_outline_rounded,
                color: Colors.white, size: 24),
            const SizedBox(width: 8),
            Text('حذف',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                )),
          ],
        ),
      ),
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        decoration: BoxDecoration(
          color: isDark ? AppColors.darkSurface : Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isDark
                ? AppColors.darkBorder
                : AppColors.border.withValues(alpha: 0.5),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: isDark ? 0.08 : 0.03),
              offset: const Offset(0, 1),
              blurRadius: 4,
            ),
          ],
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(14),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // ── Row 1: Item name + quantity × price ─────────
                  Row(
                    children: [
                      // Product icon
                      Container(
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            colors: [_accentBlue, _accentPurple],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Icon(
                          Icons.inventory_2_rounded,
                          color: Colors.white,
                          size: 18,
                        ),
                      ),
                      const SizedBox(width: 10),

                      // Item name
                      Expanded(
                        child: Text(
                          item.productName,
                          style: theme.textTheme.bodyLarge?.copyWith(
                            fontWeight: FontWeight.w700,
                            fontSize: 14,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 8),

                      // quantity × price
                      Text(
                        '${item.quantity.toStringAsFixed(item.quantity == item.quantity.truncate() ? 0 : 3)} × ${CurrencyFormatter.formatValue(item.unitPrice)}',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: isDark
                              ? AppColors.darkTextSecondary
                              : AppColors.textSecondary,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      if (item.unitName != null &&
                          item.unitName!.isNotEmpty) ...[
                        const SizedBox(width: 5),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 5, vertical: 1),
                          decoration: BoxDecoration(
                            color: _accentBlue.withValues(alpha: 0.08),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            item.unitName!,
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: _accentBlue,
                              fontSize: 9,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 8),

                  // ── Row 2: Quantity stepper + Total price ────────
                  Row(
                    children: [
                      // Quantity stepper
                      if (onQuantityChanged != null)
                        _QuantityStepper(
                          quantity: item.quantity,
                          onChanged: onQuantityChanged!,
                          isDark: isDark,
                        ),

                      const Spacer(),

                      // Total price
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 7),
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [
                              _accentBlue.withValues(
                                  alpha: isDark ? 0.15 : 0.08),
                              _accentPurple.withValues(
                                  alpha: isDark ? 0.08 : 0.04),
                            ],
                            begin: Alignment.centerRight,
                            end: Alignment.centerLeft,
                          ),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                              color: _accentBlue.withValues(alpha: 0.12)),
                        ),
                        child: Text(
                          CurrencyFormatter.format(item.totalPrice),
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w800,
                            color: _accentBlue,
                            fontSize: 14,
                          ),
                        ),
                      ),
                    ],
                  ),
                  if (item.unitCost > 0) ...[
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Icon(
                          Icons.account_balance_wallet_outlined,
                          size: 12,
                          color: isDark
                              ? AppColors.darkTextSecondary
                              : AppColors.textSecondary,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          'تكلفة: ${CurrencyFormatter.format(item.unitCost)}',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: isDark
                                ? AppColors.darkTextSecondary
                                : AppColors.textSecondary,
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
//  QUANTITY STEPPER (inline +/-) — Modern pill design
// ═══════════════════════════════════════════════════════════════════════════
class _QuantityStepper extends StatelessWidget {
  const _QuantityStepper({
    required this.quantity,
    required this.onChanged,
    required this.isDark,
  });

  final double quantity;
  final ValueChanged<double> onChanged;
  final bool isDark;

  static const Color _accentBlue = Color(0xFF4F6AF0);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      decoration: BoxDecoration(
        color: isDark
            ? AppColors.darkSurfaceVariant
            : AppColors.surfaceVariant.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: isDark
              ? AppColors.darkBorder
              : AppColors.border.withValues(alpha: 0.5),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _stepButton(
            icon: Icons.remove_rounded,
            onTap: () => onChanged((quantity - 1).clamp(0.001, 99999)),
          ),
          Container(
            constraints: const BoxConstraints(minWidth: 36),
            alignment: Alignment.center,
            child: Text(
              quantity.toStringAsFixed(quantity == quantity.truncate() ? 0 : 3),
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w800,
                fontSize: 13,
                color: _accentBlue,
              ),
            ),
          ),
          _stepButton(
            icon: Icons.add_rounded,
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
      child: Container(
        width: 30,
        height: 30,
        decoration: BoxDecoration(
          color: _accentBlue.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Icon(icon, size: 16, color: _accentBlue),
      ),
    );
  }
}
