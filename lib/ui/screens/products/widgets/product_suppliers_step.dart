import 'package:flutter/material.dart';

import 'product_form_helpers.dart';

// ═══════════════════════════════════════════════════════════════════
//  Step 5 – الموردين
// ═══════════════════════════════════════════════════════════════════

class ProductSuppliersStep extends StatelessWidget {
  // Controllers
  final TextEditingController supplierCodeController;

  // Values
  final int? selectedSupplierId;

  // Dropdown data
  final List<Map<String, dynamic>> suppliers;

  // Callbacks
  final ValueChanged<int?> onSupplierChanged;
  final VoidCallback onShowAddSupplierDialog;

  const ProductSuppliersStep({
    super.key,
    required this.supplierCodeController,
    required this.selectedSupplierId,
    required this.suppliers,
    required this.onSupplierChanged,
    required this.onShowAddSupplierDialog,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const StepTitle(title: 'الموردين', icon: Icons.local_shipping),

        // المورد الافتراضي (Searchable + "+" with empty state)
        ProductSearchableDropdown(
          label: 'المورد الافتراضي',
          icon: Icons.local_shipping,
          items: suppliers,
          idKey: 'id',
          nameKey: 'name',
          selectedId: selectedSupplierId,
          onChanged: onSupplierChanged,
          onAdd: onShowAddSupplierDialog,
          emptyMessage: 'أضف مورد من الإعدادات أولاً',
        ),
        const SizedBox(height: 14),

        // كود المورد للصنف
        TextFormField(
          controller: supplierCodeController,
          textInputAction: TextInputAction.done,
          decoration: const InputDecoration(
            isDense: true,
            labelText: 'كود المورد للصنف',
            prefixIcon: Icon(Icons.code),
          ),
        ),
        const SizedBox(height: 40),
      ],
    );
  }
}
