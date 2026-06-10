import 'package:flutter/material.dart';

import 'package:firstpro/core/extensions/context_extensions.dart';
import 'package:firstpro/core/theme/app_colors.dart';
import 'package:firstpro/core/viewmodels/pos_viewmodel.dart';

/// Bank Transfer payment fields widget for the POS cart.
class PosBankTransferFields extends StatelessWidget {
  const PosBankTransferFields({
    super.key,
    required this.vm,
    required this.onPickImage,
    required this.onPickImageFromGallery,
  });

  final PosViewModel vm;
  final void Function(String type) onPickImage;
  final void Function(String type) onPickImageFromGallery;

  @override
  Widget build(BuildContext context) {
    final bankPayment =
        vm.payments.where((p) => p.method == 'bank_transfer').firstOrNull;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          border: Border.all(color: AppColors.info.withValues(alpha: 0.4)),
          borderRadius: BorderRadius.circular(10),
          color: AppColors.info.withValues(alpha: 0.04),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.business, size: 18, color: AppColors.info),
                const SizedBox(width: 6),
                Text(
                  'بيانات التحويل البنكي',
                  style: context.textTheme.bodySmall?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: AppColors.info,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            TextField(
              decoration: InputDecoration(
                hintText: 'اسم البنك / مزود التحويل',
                isDense: true,
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                border:
                    OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                prefixIcon: const Icon(Icons.account_balance, size: 18),
              ),
              onChanged: (v) {
                final idx =
                    vm.payments.indexWhere((p) => p.method == 'bank_transfer');
                if (idx >= 0) {
                  vm.updatePayment(
                      idx, vm.payments[idx].copyWith(providerName: v));
                }
              },
              controller: TextEditingController(
                  text: bankPayment?.providerName ?? '')
                ..selection = TextSelection.fromPosition(
                  TextPosition(offset: bankPayment?.providerName?.length ?? 0),
                ),
            ),
            const SizedBox(height: 8),
            TextField(
              decoration: InputDecoration(
                hintText: 'رقم المرجع / رقم التحويل',
                isDense: true,
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                border:
                    OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                prefixIcon: const Icon(Icons.tag, size: 18),
              ),
              onChanged: (v) {
                final idx =
                    vm.payments.indexWhere((p) => p.method == 'bank_transfer');
                if (idx >= 0) {
                  vm.updatePayment(
                      idx, vm.payments[idx].copyWith(referenceNumber: v));
                }
              },
              controller: TextEditingController(
                  text: bankPayment?.referenceNumber ?? '')
                ..selection = TextSelection.fromPosition(
                  TextPosition(
                      offset: bankPayment?.referenceNumber?.length ?? 0),
                ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                OutlinedButton.icon(
                  onPressed: () => onPickImage('bank_transfer'),
                  icon: const Icon(Icons.camera_alt, size: 16),
                  label: const Text('التقاط صورة'),
                  style: OutlinedButton.styleFrom(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    textStyle: const TextStyle(fontSize: 11),
                  ),
                ),
                const SizedBox(width: 8),
                OutlinedButton.icon(
                  onPressed: () => onPickImageFromGallery('bank_transfer'),
                  icon: const Icon(Icons.image, size: 16),
                  label: const Text('إرفاق صورة'),
                  style: OutlinedButton.styleFrom(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    textStyle: const TextStyle(fontSize: 11),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
