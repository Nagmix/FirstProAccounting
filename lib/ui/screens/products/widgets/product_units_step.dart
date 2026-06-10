import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/theme/app_colors.dart';
import '../product_models.dart';
import 'product_form_helpers.dart';

// ═══════════════════════════════════════════════════════════════════
//  Step 2 – الوحدات
// ═══════════════════════════════════════════════════════════════════

class ProductUnitsStep extends StatelessWidget {
  // Controllers
  final TextEditingController costPriceController;

  // Values
  final int? selectedBaseUnitId;
  final int? selectedPurchaseUnitId;
  final int saleUnitSource; // 0 = base unit, 1 = purchase unit
  final bool hasMultiUnits;
  final double purchaseUnitFactor;

  // Unit conversions
  final List<UnitConversionRow> unitConversions;

  // Dropdown data
  final List<Map<String, dynamic>> units;

  // Helpers
  final String Function(int? id) unitNameById;

  // Callbacks
  final ValueChanged<int?> onBaseUnitChanged;
  final ValueChanged<int?> onPurchaseUnitChanged;
  final VoidCallback onShowAddUnitDialog;
  final ValueChanged<int> onSaleUnitSourceChanged;
  final VoidCallback onAddConversionRow;
  final void Function(int index) onRemoveConversionRow;
  final void Function(UnitConversionRow row, int index) onConversionChanged;
  final VoidCallback onStateChanged; // trigger setState in parent

  const ProductUnitsStep({
    super.key,
    required this.costPriceController,
    required this.selectedBaseUnitId,
    required this.selectedPurchaseUnitId,
    required this.saleUnitSource,
    required this.hasMultiUnits,
    required this.purchaseUnitFactor,
    required this.unitConversions,
    required this.units,
    required this.unitNameById,
    required this.onBaseUnitChanged,
    required this.onPurchaseUnitChanged,
    required this.onShowAddUnitDialog,
    required this.onSaleUnitSourceChanged,
    required this.onAddConversionRow,
    required this.onRemoveConversionRow,
    required this.onConversionChanged,
    required this.onStateChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const StepTitle(title: 'الوحدات', icon: Icons.straighten),

        // ── الوحدة الأساسية * (Searchable + "+") ────────────
        ProductSearchableDropdown(
          label: 'الوحدة الأساسية *',
          icon: Icons.straighten,
          items: units,
          idKey: 'id',
          nameKey: 'name_ar',
          selectedId: selectedBaseUnitId,
          onChanged: onBaseUnitChanged,
          onAdd: onShowAddUnitDialog,
        ),
        const SizedBox(height: 14),

        // ── وحدة الشراء الافتراضية (Searchable + "+") ───────
        ProductSearchableDropdown(
          label: 'وحدة الشراء الافتراضية',
          icon: Icons.shopping_cart,
          items: units,
          idKey: 'id',
          nameKey: 'name_ar',
          selectedId: selectedPurchaseUnitId,
          onChanged: onPurchaseUnitChanged,
          onAdd: onShowAddUnitDialog,
        ),
        const SizedBox(height: 14),

        // ── وحدة البيع الافتراضية (Checkbox approach) ───────
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            border: Border.all(color: AppColors.border),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('وحدة البيع الافتراضية',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      )),
              const SizedBox(height: 8),
              // Checkbox for base unit
              _buildSaleUnitCheckbox(
                context: context,
                label: selectedBaseUnitId != null
                    ? '${unitNameById(selectedBaseUnitId)} (الوحدة الأساسية)'
                    : 'الوحدة الأساسية',
                value: saleUnitSource == 0,
                onChanged: (v) {
                  if (v == true) {
                    onSaleUnitSourceChanged(0);
                  }
                },
              ),
              // Checkbox for purchase unit
              _buildSaleUnitCheckbox(
                context: context,
                label: selectedPurchaseUnitId != null
                    ? '${unitNameById(selectedPurchaseUnitId)} (وحدة الشراء)'
                    : 'وحدة الشراء الافتراضية',
                value: saleUnitSource == 1,
                onChanged: (v) {
                  if (v == true && selectedPurchaseUnitId != null) {
                    onSaleUnitSourceChanged(1);
                  } else if (selectedPurchaseUnitId == null) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('يجب اختيار وحدة الشراء أولاً'),
                        backgroundColor: AppColors.warning,
                      ),
                    );
                  }
                },
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),

        // ── جدول التحويلات ──────────────────────────────────
        Row(
          children: [
            Icon(Icons.swap_horiz, size: 20, color: AppColors.primary),
            const SizedBox(width: 8),
            Text(
              'جدول التحويلات',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: AppColors.primary,
                  ),
            ),
            const Spacer(),
            TextButton.icon(
              onPressed: onAddConversionRow,
              icon: const Icon(Icons.add, size: 18),
              label: const Text('إضافة تحويل'),
              style: TextButton.styleFrom(foregroundColor: AppColors.primary),
            ),
          ],
        ),
        const SizedBox(height: 8),

        // Info card
        if (selectedBaseUnitId != null)
          Container(
            padding: const EdgeInsets.all(10),
            margin: const EdgeInsets.only(bottom: 12),
            decoration: BoxDecoration(
              color: AppColors.infoLight.withValues(alpha: 0.5),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: AppColors.info.withValues(alpha: 0.2)),
            ),
            child: Row(
              children: [
                const Icon(Icons.info_outline, size: 18, color: AppColors.info),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'كم ${unitNameById(selectedBaseUnitId)} تساوي الوحدة الأكبر؟',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: AppColors.info,
                        ),
                  ),
                ),
              ],
            ),
          ),

        // Conversion rows
        if (unitConversions.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 24),
            child: Center(
              child: Column(
                children: [
                  Icon(Icons.add_circle_outline,
                      size: 40,
                      color: AppColors.textTertiary.withValues(alpha: 0.4)),
                  const SizedBox(height: 8),
                  Text('لا توجد تحويلات',
                      style: TextStyle(
                          color:
                              AppColors.textTertiary.withValues(alpha: 0.6))),
                  const SizedBox(height: 4),
                  Text('اضغط "إضافة تحويل" لتحديد وحدة أكبر',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: AppColors.textTertiary,
                          )),
                ],
              ),
            ),
          )
        else ...[
          // Header row
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            decoration: BoxDecoration(
              color: AppColors.surfaceVariant,
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Row(
              children: [
                Expanded(
                    flex: 3,
                    child: Text('الوحدة',
                        style: TextStyle(
                            fontWeight: FontWeight.w700, fontSize: 12))),
                Expanded(
                    flex: 3,
                    child: Text('معامل التحويل',
                        style: TextStyle(
                            fontWeight: FontWeight.w700, fontSize: 12))),
                Expanded(
                    flex: 2,
                    child: Text('سعر البيع',
                        style: TextStyle(
                            fontWeight: FontWeight.w700, fontSize: 12))),
                Expanded(
                    flex: 2,
                    child: Text('سعر التكلفة',
                        style: TextStyle(
                            fontWeight: FontWeight.w700, fontSize: 12))),
                SizedBox(width: 40),
              ],
            ),
          ),
          const SizedBox(height: 6),
          ...List.generate(unitConversions.length, (i) {
            final row = unitConversions[i];
            return _buildConversionRow(context, row, i);
          }),
        ],
        const SizedBox(height: 40),
      ],
    );
  }

  // ── Private helpers ────────────────────────────────────────────

  Widget _buildSaleUnitCheckbox({
    required BuildContext context,
    required String label,
    required bool value,
    required ValueChanged<bool?> onChanged,
  }) {
    return InkWell(
      onTap: () => onChanged(!value),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          children: [
            Checkbox(
              value: value,
              onChanged: onChanged,
              activeColor: AppColors.primary,
            ),
            const SizedBox(width: 4),
            Expanded(
              child: Text(label,
                  style: TextStyle(
                    fontWeight: value ? FontWeight.w600 : FontWeight.w400,
                    color: value ? AppColors.primary : AppColors.textSecondary,
                  )),
            ),
            if (value)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text('وحدة بيع افتراضية',
                    style: TextStyle(
                        fontSize: 10,
                        color: AppColors.primary,
                        fontWeight: FontWeight.w600)),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildConversionRow(
      BuildContext context, UnitConversionRow row, int index) {
    final baseUnitName = unitNameById(selectedBaseUnitId);

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      decoration: BoxDecoration(
        border: Border.all(color: AppColors.border),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          // Unit dropdown
          Expanded(
            flex: 3,
            child: DropdownButtonFormField<int>(
              value: row.unitId,
              isDense: true,
              decoration: const InputDecoration(
                isDense: true,
                labelText: 'الوحدة',
                contentPadding:
                    EdgeInsets.symmetric(horizontal: 8, vertical: 8),
              ),
              items: units
                  .where((u) => u['id'] != selectedBaseUnitId)
                  .map((u) => DropdownMenuItem<int>(
                        value: u['id'] as int,
                        child: Text(u['name_ar'] as String,
                            style: const TextStyle(fontSize: 13),
                            overflow: TextOverflow.ellipsis),
                      ))
                  .toList(),
              onChanged: (v) {
                row.unitId = v;
                onStateChanged();
              },
            ),
          ),
          const SizedBox(width: 6),

          // Factor field
          Expanded(
            flex: 3,
            child: TextFormField(
              initialValue:
                  row.factor == 1.0 ? '' : row.factor.toStringAsFixed(0),
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d{0,4}')),
              ],
              decoration: InputDecoration(
                isDense: true,
                labelText: row.unitId != null
                    ? '${unitNameById(row.unitId)} كم $baseUnitName؟'
                    : 'الكمية',
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
              ),
              onChanged: (v) {
                row.factor = double.tryParse(v) ?? 1.0;
                onConversionChanged(row, index);
                onStateChanged();
              },
            ),
          ),
          const SizedBox(width: 6),

          // Sell price
          Expanded(
            flex: 2,
            child: TextFormField(
              initialValue:
                  row.sellPrice > 0 ? row.sellPrice.toStringAsFixed(2) : '',
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d{0,2}')),
              ],
              decoration: const InputDecoration(
                isDense: true,
                labelText: 'سعر البيع',
                contentPadding:
                    EdgeInsets.symmetric(horizontal: 8, vertical: 8),
              ),
              onChanged: (v) => row.sellPrice = double.tryParse(v) ?? 0.0,
            ),
          ),
          const SizedBox(width: 6),

          // Cost price — auto-calculated from Step3 purchase unit cost price
          Expanded(
            flex: 2,
            child: _buildAutoCostPriceField(context, row),
          ),

          // Delete
          IconButton(
            icon: Icon(Icons.delete_outline,
                size: 20, color: AppColors.error.withValues(alpha: 0.7)),
            onPressed: () => onRemoveConversionRow(index),
          ),
        ],
      ),
    );
  }

  /// Build auto-calculated cost price field for conversion row.
  Widget _buildAutoCostPriceField(BuildContext context, UnitConversionRow row) {
    final purchaseUnitCost = double.tryParse(costPriceController.text) ?? 0.0;
    final baseUnitName = unitNameById(selectedBaseUnitId);

    double autoCost = 0.0;
    if (hasMultiUnits && purchaseUnitCost > 0 && row.factor > 0) {
      if (row.unitId == selectedPurchaseUnitId) {
        autoCost = purchaseUnitCost;
      } else {
        final pf = purchaseUnitFactor;
        if (pf > 0) {
          final baseUnitCost = purchaseUnitCost / pf;
          autoCost = baseUnitCost * row.factor;
        }
      }
    }

    // Update the row's costPrice with auto-calculated value
    if (autoCost > 0) {
      row.costPrice = autoCost;
    }

    return TextFormField(
      initialValue: autoCost > 0
          ? autoCost.toStringAsFixed(2)
          : (row.costPrice > 0 ? row.costPrice.toStringAsFixed(2) : ''),
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      inputFormatters: [
        FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d{0,2}')),
      ],
      decoration: InputDecoration(
        isDense: true,
        labelText: row.unitId == selectedPurchaseUnitId && hasMultiUnits
            ? 'تكلفة $baseUnitName'
            : 'سعر التكلفة',
        contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        suffixIcon: autoCost > 0
            ? Tooltip(
                message: 'محسوب تلقائياً من سعر تكلفة وحدة الشراء',
                child: Icon(Icons.auto_fix_high,
                    size: 16, color: AppColors.success.withValues(alpha: 0.7)),
              )
            : null,
      ),
      onChanged: (v) => row.costPrice = double.tryParse(v) ?? 0.0,
    );
  }
}
