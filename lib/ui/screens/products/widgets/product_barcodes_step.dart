import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../widgets/barcode_scanner_screen.dart';
import '../product_models.dart';
import 'product_form_helpers.dart';

// ═══════════════════════════════════════════════════════════════════
//  Barcode entry helper
// ═══════════════════════════════════════════════════════════════════

class _BarcodeEntry {
  final String unitName;
  String barcode;
  final UnitConversionRow? conversionRow;
  final bool isPurchaseUnit;

  _BarcodeEntry({
    required this.unitName,
    required this.barcode,
    this.conversionRow,
    this.isPurchaseUnit = false,
  });
}

// ═══════════════════════════════════════════════════════════════════
//  Step 6 – الباركود
// ═══════════════════════════════════════════════════════════════════

class ProductBarcodesStep extends StatelessWidget {
  // Values
  final int? selectedBaseUnitId;
  final int? selectedPurchaseUnitId;
  final List<UnitConversionRow> unitConversions;

  // Helpers
  final String Function(int? id) unitNameById;

  // Callbacks
  final VoidCallback onStateChanged;

  const ProductBarcodesStep({
    super.key,
    required this.selectedBaseUnitId,
    required this.selectedPurchaseUnitId,
    required this.unitConversions,
    required this.unitNameById,
    required this.onStateChanged,
  });

  @override
  Widget build(BuildContext context) {
    // Build barcode list from conversions + purchase unit (NOT base unit)
    final List<_BarcodeEntry> barcodes = [];

    // Add conversion units
    for (final uc in unitConversions) {
      barcodes.add(_BarcodeEntry(
        unitName: unitNameById(uc.unitId),
        barcode: uc.barcode,
        conversionRow: uc,
      ));
    }

    // Add purchase unit if not already in conversions
    if (selectedPurchaseUnitId != null &&
        selectedPurchaseUnitId != selectedBaseUnitId &&
        !unitConversions.any((uc) => uc.unitId == selectedPurchaseUnitId)) {
      barcodes.add(_BarcodeEntry(
        unitName: unitNameById(selectedPurchaseUnitId),
        barcode: '',
        isPurchaseUnit: true,
      ));
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const StepTitle(title: 'الباركود', icon: Icons.qr_code),

        // Info: base unit barcode is in step 1
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
                  'باركود ${unitNameById(selectedBaseUnitId)} أُدخل في الخطوة الأولى',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: AppColors.info,
                      ),
                ),
              ),
            ],
          ),
        ),

        if (barcodes.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 24),
            child: Center(
              child: Column(
                children: [
                  Icon(Icons.qr_code,
                      size: 40,
                      color: AppColors.textTertiary.withValues(alpha: 0.4)),
                  const SizedBox(height: 8),
                  Text('لا توجد وحدات أخرى',
                      style: TextStyle(
                          color:
                              AppColors.textTertiary.withValues(alpha: 0.6))),
                  const SizedBox(height: 4),
                  Text('أضف وحدات أكبر في خطوة الوحدات أولاً',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: AppColors.textTertiary,
                          )),
                ],
              ),
            ),
          )
        else ...[
          // Header
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: AppColors.surfaceVariant,
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Row(
              children: [
                Expanded(
                    flex: 2,
                    child: Text('الوحدة',
                        style: TextStyle(
                            fontWeight: FontWeight.w700, fontSize: 13))),
                Expanded(
                    flex: 3,
                    child: Text('باركود',
                        style: TextStyle(
                            fontWeight: FontWeight.w700, fontSize: 13))),
              ],
            ),
          ),
          const SizedBox(height: 6),

          ...List.generate(barcodes.length, (i) {
            final entry = barcodes[i];
            return Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                border: Border.all(color: AppColors.border),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  // Unit name
                  Expanded(
                    flex: 2,
                    child: Text(
                      entry.unitName,
                      style: const TextStyle(
                          fontWeight: FontWeight.w600, fontSize: 13),
                    ),
                  ),
                  const SizedBox(width: 8),

                  // Barcode field with scan button
                  Expanded(
                    flex: 3,
                    child: TextFormField(
                      initialValue: entry.barcode,
                      decoration: InputDecoration(
                        isDense: true,
                        hintText: 'أدخل الباركود',
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 8),
                        suffixIcon: IconButton(
                          icon: const Icon(Icons.camera_alt, size: 16),
                          onPressed: () async {
                            final result = await Navigator.push<String>(
                              context,
                              MaterialPageRoute(
                                  builder: (_) => const BarcodeScannerScreen()),
                            );
                            if (result != null && result.isNotEmpty) {
                              if (entry.conversionRow != null) {
                                entry.conversionRow!.barcode = result;
                              }
                              onStateChanged();
                            }
                          },
                        ),
                      ),
                      onChanged: (v) {
                        if (entry.conversionRow != null) {
                          entry.conversionRow!.barcode = v;
                        }
                      },
                    ),
                  ),
                ],
              ),
            );
          }),
        ],
        const SizedBox(height: 40),
      ],
    );
  }
}
