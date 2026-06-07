import 'dart:io';

import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import 'product_form_helpers.dart';

// ═══════════════════════════════════════════════════════════════════
//  Step 1 – البيانات الأساسية
// ═══════════════════════════════════════════════════════════════════

class ProductBasicDataStep extends StatelessWidget {
  // Controllers
  final TextEditingController nameArController;
  final TextEditingController nameEnController;
  final TextEditingController itemCodeController;
  final TextEditingController barcodeController;
  final TextEditingController descriptionController;
  final TextEditingController notesController;

  // Values
  final int? selectedCategoryId;
  final String? imagePath;
  final bool isActive;

  // Dropdown data
  final List<Map<String, dynamic>> categories;

  // Callbacks
  final VoidCallback onPickImage;
  final VoidCallback onImageRemoved;
  final VoidCallback onGenerateItemCode;
  final VoidCallback onScanBarcode;
  final VoidCallback onBarcodeCleared;
  final ValueChanged<int?> onCategoryChanged;
  final VoidCallback onShowAddCategoryDialog;
  final ValueChanged<bool> onActiveChanged;
  final VoidCallback onBarcodeChanged;

  const ProductBasicDataStep({
    super.key,
    required this.nameArController,
    required this.nameEnController,
    required this.itemCodeController,
    required this.barcodeController,
    required this.descriptionController,
    required this.notesController,
    required this.selectedCategoryId,
    required this.imagePath,
    required this.isActive,
    required this.categories,
    required this.onPickImage,
    required this.onImageRemoved,
    required this.onGenerateItemCode,
    required this.onScanBarcode,
    required this.onBarcodeCleared,
    required this.onCategoryChanged,
    required this.onShowAddCategoryDialog,
    required this.onActiveChanged,
    required this.onBarcodeChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const StepTitle(title: 'البيانات الأساسية', icon: Icons.article),

        // ── Image ─────────────────────────────────────────────
        Center(
          child: GestureDetector(
            onTap: onPickImage,
            child: Container(
              width: 120,
              height: 120,
              decoration: BoxDecoration(
                color: AppColors.primary.withOpacity(0.06),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: AppColors.primary.withOpacity(0.2),
                  style: BorderStyle.solid,
                ),
              ),
              child: imagePath != null
                  ? ClipRRect(
                      borderRadius: BorderRadius.circular(16),
                      child: Image.file(
                        File(imagePath!),
                        width: 120,
                        height: 120,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => Icon(
                          Icons.image,
                          size: 40,
                          color: AppColors.primary.withOpacity(0.4),
                        ),
                      ),
                    )
                  : Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.camera_alt,
                            size: 32,
                            color: AppColors.primary.withOpacity(0.5)),
                        const SizedBox(height: 6),
                        Text('صورة الصنف',
                            style: TextStyle(
                                fontSize: 12,
                                color: AppColors.primary.withOpacity(0.7))),
                      ],
                    ),
            ),
          ),
        ),
        if (imagePath != null) ...[
          const SizedBox(height: 4),
          Center(
            child: TextButton.icon(
              onPressed: onImageRemoved,
              icon: const Icon(Icons.delete, size: 16, color: AppColors.error),
              label: const Text('إزالة الصورة',
                  style: TextStyle(color: AppColors.error, fontSize: 12)),
            ),
          ),
        ],
        const SizedBox(height: 16),

        // ── اسم الصنف بالعربي * ─────────────────────────────
        TextFormField(
          controller: nameArController,
          textInputAction: TextInputAction.next,
          decoration: const InputDecoration(
            isDense: true,
            labelText: 'اسم الصنف بالعربي *',
            prefixIcon: Icon(Icons.text_fields),
          ),
          validator: (v) =>
              (v == null || v.trim().isEmpty) ? 'اسم الصنف بالعربي مطلوب' : null,
        ),
        const SizedBox(height: 14),

        // ── اسم الصنف بالإنجليزي ────────────────────────────
        TextFormField(
          controller: nameEnController,
          textInputAction: TextInputAction.next,
          decoration: const InputDecoration(
            isDense: true,
            labelText: 'اسم الصنف بالإنجليزي',
            prefixIcon: Icon(Icons.text_fields),
          ),
        ),
        const SizedBox(height: 14),

        // ── SKU / رمز الصنف ─────────────────────────────────
        TextFormField(
          controller: itemCodeController,
          textInputAction: TextInputAction.next,
          decoration: InputDecoration(
            isDense: true,
            labelText: 'SKU / رمز الصنف',
            prefixIcon: const Icon(Icons.tag),
            suffixIcon: IconButton(
              icon: const Icon(Icons.refresh, size: 18),
              tooltip: 'توليد رمز جديد',
              onPressed: onGenerateItemCode,
            ),
          ),
        ),
        const SizedBox(height: 14),

        // ── باركود ──────────────────────────────────────────
        TextFormField(
          controller: barcodeController,
          textInputAction: TextInputAction.next,
          decoration: InputDecoration(
            isDense: true,
            labelText: 'باركود',
            prefixIcon: const Icon(Icons.qr_code),
            suffixIcon: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (barcodeController.text.isNotEmpty)
                  IconButton(
                    icon: const Icon(Icons.close, size: 18),
                    onPressed: onBarcodeCleared,
                  ),
                IconButton(
                  icon: const Icon(Icons.camera_alt, size: 20),
                  tooltip: 'مسح الباركود بالكاميرا',
                  onPressed: onScanBarcode,
                ),
              ],
            ),
          ),
          onChanged: (_) => onBarcodeChanged(),
        ),
        const SizedBox(height: 14),

        // ── التصنيف (Searchable + "+" button) ────────────────
        ProductSearchableDropdown(
          label: 'التصنيف',
          icon: Icons.folder,
          items: categories,
          idKey: 'id',
          nameKey: 'name',
          selectedId: selectedCategoryId,
          onChanged: onCategoryChanged,
          onAdd: onShowAddCategoryDialog,
        ),
        const SizedBox(height: 14),

        // ── وصف الصنف ───────────────────────────────────────
        TextFormField(
          controller: descriptionController,
          textInputAction: TextInputAction.next,
          maxLines: 2,
          minLines: 1,
          decoration: const InputDecoration(
            isDense: true,
            labelText: 'وصف الصنف',
            prefixIcon: Icon(Icons.edit_note),
            alignLabelWithHint: true,
          ),
        ),
        const SizedBox(height: 14),

        // ── حالة الصنف ─────────────────────────────────────
        ProductSwitchTile(
          title: 'حالة الصنف',
          subtitle: isActive ? 'نشط' : 'غير نشط',
          value: isActive,
          onChanged: onActiveChanged,
        ),
        const SizedBox(height: 14),

        // ── ملاحظات ─────────────────────────────────────────
        TextFormField(
          controller: notesController,
          textInputAction: TextInputAction.done,
          maxLines: 2,
          minLines: 1,
          decoration: const InputDecoration(
            isDense: true,
            labelText: 'ملاحظات',
            prefixIcon: Icon(Icons.note),
            alignLabelWithHint: true,
          ),
        ),
        const SizedBox(height: 40),
      ],
    );
  }
}
