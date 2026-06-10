import 'package:flutter/material.dart';

import '../../../../core/extensions/context_extensions.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../data/models/invoice_item_model.dart';
import '../../../widgets/invoice_item_card.dart';

/// Extracted items section widget for the CreateInvoiceScreen.
///
/// Receives the items list and callbacks for mutations.
class InvoiceItemsSection extends StatelessWidget {
  const InvoiceItemsSection({
    super.key,
    required this.isDark,
    required this.items,
    required this.onQuantityChanged,
    required this.onDeleteItem,
    required this.onAddItem,
  });

  // ── State values ─────────────────────────────────────────────────
  final bool isDark;
  final List<InvoiceItem> items;

  // ── Callbacks ────────────────────────────────────────────────────
  /// Called when the quantity of item at [index] is changed to [qty].
  final void Function(int index, double qty) onQuantityChanged;

  /// Called when the item at [index] should be deleted.
  final void Function(int index) onDeleteItem;

  /// Called when the user wants to add a new item.
  final VoidCallback onAddItem;

  // ── Design constants (duplicated from parent) ────────────────────
  static const Color _accentBlue = Color(0xFF4F6AF0);
  static const Color _accentPurple = Color(0xFF7C3AED);

  LinearGradient get _primaryGradient => const LinearGradient(
        colors: [_accentBlue, _accentPurple],
        begin: Alignment.centerRight,
        end: Alignment.centerLeft,
      );

  // ── Section header helper ────────────────────────────────────────
  Widget _sectionHeader(BuildContext context, String title,
      {IconData icon = Icons.label_important_rounded, Widget? trailing}) {
    final isDark = context.isDarkMode;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          Container(
            width: 4,
            height: 22,
            decoration: BoxDecoration(
              gradient: _primaryGradient,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 10),
          Icon(icon, size: 20, color: _accentBlue),
          const SizedBox(width: 8),
          Expanded(
            child: Text(title,
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 16,
                  letterSpacing: 0.3,
                  color: isDark ? AppColors.darkTextPrimary : const Color(0xFF1E293B),
                )),
          ),
          if (trailing != null) trailing,
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkSurface : Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.12 : 0.04),
            offset: const Offset(0, 2),
            blurRadius: 8,
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionHeader(
            context,
            'الأصناف',
            icon: Icons.inventory_2_rounded,
            trailing: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                gradient: _primaryGradient,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text('${items.length}',
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 12)),
            ),
          ),
          if (items.isEmpty)
            Container(
              padding: const EdgeInsets.all(28),
              decoration: BoxDecoration(
                color: isDark ? AppColors.darkSurfaceVariant : AppColors.surfaceVariant.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: isDark ? AppColors.darkBorder : AppColors.border,
                  style: BorderStyle.solid,
                ),
              ),
              child: Center(
                child: Column(
                  children: [
                    Container(
                      width: 56,
                      height: 56,
                      decoration: BoxDecoration(
                        color: _accentBlue.withValues(alpha: 0.06),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(Icons.shopping_cart_outlined, size: 28, color: _accentBlue.withValues(alpha: 0.4)),
                    ),
                    const SizedBox(height: 10),
                    Text('لم يتم إضافة أصناف بعد',
                        style: context.textTheme.bodySmall?.copyWith(color: AppColors.textHint, fontWeight: FontWeight.w500)),
                  ],
                ),
              ),
            )
          else
            ...items.asMap().entries.map((entry) {
              final index = entry.key;
              final item = entry.value;
              return InvoiceItemCard(
                item: item,
                onQuantityChanged: (qty) => onQuantityChanged(index, qty),
                onDelete: () => onDeleteItem(index),
              );
            }),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: _accentBlue.withValues(alpha: 0.3)),
              ),
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: onAddItem,
                  borderRadius: BorderRadius.circular(12),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Container(
                          width: 24,
                          height: 24,
                          decoration: BoxDecoration(
                            color: _accentBlue.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(7),
                          ),
                          child: const Icon(Icons.add_rounded, size: 16, color: _accentBlue),
                        ),
                        const SizedBox(width: 8),
                        Text('إضافة صنف',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                              color: _accentBlue,
                            )),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
