import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:firstpro/core/theme/app_colors.dart';
import 'package:firstpro/data/models/product_model.dart';
import 'package:firstpro/ui/screens/products/widgets/product_form_helpers.dart';

// ═══════════════════════════════════════════════════════════════════
//  Step 4 – المخزون
// ═══════════════════════════════════════════════════════════════════

class ProductInventoryStep extends StatelessWidget {
  // Controllers
  final TextEditingController openingStockController;
  final TextEditingController purchaseUnitQtyController;
  final TextEditingController minStockController;
  final TextEditingController maxStockController;

  // Values
  final bool hasMultiUnits;
  final double purchaseUnitFactor;
  final bool trackStock;
  final bool expiryTracking;
  final DateTime? expiryDate;
  final int? selectedWarehouseId;
  final int? selectedBaseUnitId;
  final int? selectedPurchaseUnitId;
  final bool isEditMode;
  final Product? existingProduct;

  // Dropdown data
  final List<Map<String, dynamic>> warehouses;

  // Helpers
  final String Function(int? id) unitNameById;

  // Callbacks
  final ValueChanged<bool> onTrackStockChanged;
  final ValueChanged<bool> onExpiryTrackingChanged;
  final VoidCallback onPickExpiryDate;
  final ValueChanged<int?> onWarehouseChanged;
  final VoidCallback onShowAddWarehouseDialog;
  final VoidCallback onAutoCalculateOpeningStock;
  final VoidCallback onStateChanged;

  const ProductInventoryStep({
    super.key,
    required this.openingStockController,
    required this.purchaseUnitQtyController,
    required this.minStockController,
    required this.maxStockController,
    required this.hasMultiUnits,
    required this.purchaseUnitFactor,
    required this.trackStock,
    required this.expiryTracking,
    required this.expiryDate,
    required this.selectedWarehouseId,
    required this.selectedBaseUnitId,
    required this.selectedPurchaseUnitId,
    required this.isEditMode,
    required this.existingProduct,
    required this.warehouses,
    required this.unitNameById,
    required this.onTrackStockChanged,
    required this.onExpiryTrackingChanged,
    required this.onPickExpiryDate,
    required this.onWarehouseChanged,
    required this.onShowAddWarehouseDialog,
    required this.onAutoCalculateOpeningStock,
    required this.onStateChanged,
  });

  @override
  Widget build(BuildContext context) {
    final purchaseUnitName = unitNameById(selectedPurchaseUnitId);
    final baseUnitName = unitNameById(selectedBaseUnitId);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const StepTitle(title: 'المخزون', icon: Icons.inventory),

        // تتبع المخزون
        ProductSwitchTile(
          title: 'تتبع المخزون',
          subtitle: trackStock ? 'مفعّل' : 'معطّل',
          value: trackStock,
          onChanged: onTrackStockChanged,
        ),
        const SizedBox(height: 14),

        // كمية افتتاحية (new products only)
        if (!isEditMode) ...[
          // ── Multi-unit: purchase unit quantity → auto-calculate base unit qty ──
          if (hasMultiUnits) ...[
            TextFormField(
              controller: purchaseUnitQtyController,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              textInputAction: TextInputAction.next,
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d{0,3}')),
              ],
              decoration: InputDecoration(
                isDense: true,
                labelText: 'عدد $purchaseUnitName المشتراة',
                prefixIcon: const Icon(Icons.add_shopping_cart),
                suffixText: purchaseUnitName,
              ),
              onChanged: (v) {
                onAutoCalculateOpeningStock();
                onStateChanged();
              },
            ),
            const SizedBox(height: 8),

            // Simple auto-calculation display
            if (purchaseUnitQtyController.text.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Text(
                  '↪ الكمية = ${_calculateOpeningStockDisplay()} $baseUnitName',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: AppColors.success,
                        fontWeight: FontWeight.w600,
                      ),
                ),
              ),
          ],

          TextFormField(
            controller: openingStockController,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            textInputAction: TextInputAction.next,
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d{0,3}')),
            ],
            decoration: InputDecoration(
              isDense: true,
              labelText: hasMultiUnits
                  ? 'إجمالي الكمية ($baseUnitName)'
                  : 'الكمية الافتتاحية',
              prefixIcon: const Icon(Icons.inventory),
              suffixText: baseUnitName,
            ),
          ),
          const SizedBox(height: 14),
        ] else ...[
          // Show current stock (locked)
          Container(
            padding: const EdgeInsets.all(12),
            margin: const EdgeInsets.only(bottom: 14),
            decoration: BoxDecoration(
              color: AppColors.surfaceVariant,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: AppColors.border),
            ),
            child: Row(
              children: [
                const Icon(Icons.lock, size: 18, color: AppColors.textTertiary),
                const SizedBox(width: 8),
                Text(
                  'الرصيد الحالي: ${existingProduct?.currentStock.toStringAsFixed(0) ?? '0'} ${unitNameById(selectedBaseUnitId)}',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: AppColors.textSecondary,
                      ),
                ),
              ],
            ),
          ),
        ],

        // مستودع افتراضي (Searchable + "+" with empty state)
        ProductSearchableDropdown(
          label: 'مستودع افتراضي',
          icon: Icons.warehouse,
          items: warehouses,
          idKey: 'id',
          nameKey: 'name',
          selectedId: selectedWarehouseId,
          onChanged: isEditMode ? null : onWarehouseChanged,
          onAdd: onShowAddWarehouseDialog,
          emptyMessage: 'أضف مستودع من الإعدادات أولاً',
        ),
        const SizedBox(height: 14),

        // الحد الأدنى + الحد الأعلى
        Row(
          children: [
            Expanded(
              child: TextFormField(
                controller: minStockController,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                textInputAction: TextInputAction.next,
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d{0,3}')),
                ],
                decoration: InputDecoration(
                  isDense: true,
                  labelText: 'الحد الأدنى',
                  prefixIcon: const Icon(Icons.vertical_align_bottom),
                  suffixText: unitNameById(selectedBaseUnitId),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: TextFormField(
                controller: maxStockController,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                textInputAction: TextInputAction.next,
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d{0,3}')),
                ],
                decoration: InputDecoration(
                  isDense: true,
                  labelText: 'الحد الأعلى',
                  prefixIcon: const Icon(Icons.vertical_align_top),
                  suffixText: unitNameById(selectedBaseUnitId),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),

        // تتبع الصلاحية
        ProductSwitchTile(
          title: 'تتبع الصلاحية',
          subtitle: expiryTracking ? 'مفعّل' : 'معطّل',
          value: expiryTracking,
          onChanged: onExpiryTrackingChanged,
        ),
        if (expiryTracking) ...[
          const SizedBox(height: 10),
          ListTile(
            dense: true,
            contentPadding: const EdgeInsets.symmetric(horizontal: 4),
            leading: const Icon(Icons.calendar_today, size: 20),
            title: Text(
              expiryDate != null
                  ? 'تاريخ الانتهاء: ${expiryDate!.day}/${expiryDate!.month}/${expiryDate!.year}'
                  : 'تحديد تاريخ الانتهاء',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            trailing: const Icon(Icons.chevron_left),
            onTap: onPickExpiryDate,
            shape: RoundedRectangleBorder(
              side: BorderSide(color: AppColors.border),
              borderRadius: BorderRadius.circular(8),
            ),
          ),
        ],
        const SizedBox(height: 40),
      ],
    );
  }

  /// Display string for auto-calculated opening stock
  String _calculateOpeningStockDisplay() {
    final purchaseQty = double.tryParse(purchaseUnitQtyController.text);
    if (purchaseQty == null || purchaseQty <= 0) return '...';
    final factor = purchaseUnitFactor;
    if (factor <= 0) return '...';
    final totalBaseQty = purchaseQty * factor;
    return totalBaseQty.toStringAsFixed(0);
  }
}
