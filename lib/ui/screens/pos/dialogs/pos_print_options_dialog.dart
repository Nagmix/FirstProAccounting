import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';

/// Shows the print options bottom sheet (PDF or Bluetooth thermal).
void showPrintOptionsDialog(
  BuildContext context,
  String invoiceId, {
  required Future<void> Function(String) onPdfPrint,
  required Future<void> Function(String) onBluetoothPrint,
}) {
  showModalBottomSheet(
    context: context,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (ctx) => Directionality(
      textDirection: TextDirection.rtl,
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('خيارات الطباعة', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
              const SizedBox(height: 20),
              ListTile(
                leading: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.picture_as_pdf, color: AppColors.primary),
                ),
                title: const Text('طباعة PDF', style: TextStyle(fontWeight: FontWeight.w700)),
                subtitle: const Text('مشاركة أو حفظ كملف PDF'),
                trailing: const Icon(Icons.arrow_back_ios, size: 16),
                onTap: () async {
                  Navigator.pop(ctx);
                  await onPdfPrint(invoiceId);
                },
              ),
              const SizedBox(height: 8),
              ListTile(
                leading: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: AppColors.accentBlue.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.bluetooth, color: AppColors.accentBlue),
                ),
                title: const Text('طباعة حرارية بلوتوث', style: TextStyle(fontWeight: FontWeight.w700)),
                subtitle: const Text('طباعة على طابعة حرارية 80mm'),
                trailing: const Icon(Icons.arrow_back_ios, size: 16),
                onTap: () {
                  Navigator.pop(ctx);
                  onBluetoothPrint(invoiceId);
                },
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
