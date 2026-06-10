import 'package:flutter/material.dart';

import '../../../../core/extensions/context_extensions.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/viewmodels/pos_viewmodel.dart';

/// E-Wallet payment fields widget for the POS cart.
class PosEwalletFields extends StatelessWidget {
  const PosEwalletFields({
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
    final ewalletPayment =
        vm.payments.where((p) => p.method == 'ewallet').firstOrNull;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          border: Border.all(color: AppColors.secondary.withValues(alpha: 0.4)),
          borderRadius: BorderRadius.circular(10),
          color: AppColors.secondary.withValues(alpha: 0.04),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.account_balance_wallet,
                    size: 18, color: AppColors.secondary),
                const SizedBox(width: 6),
                Text(
                  'بيانات المحفظة الإلكترونية',
                  style: context.textTheme.bodySmall?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: AppColors.secondary,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            TextField(
              decoration: InputDecoration(
                hintText: 'اسم مزود المحفظة (مثل: فلوسك، جوالي)',
                isDense: true,
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                border:
                    OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                prefixIcon: const Icon(Icons.badge, size: 18),
              ),
              onChanged: (v) {
                // Update the ewallet provider name in payments
                final idx =
                    vm.payments.indexWhere((p) => p.method == 'ewallet');
                if (idx >= 0) {
                  vm.updatePayment(
                      idx, vm.payments[idx].copyWith(providerName: v));
                }
              },
              controller: TextEditingController(
                  text: ewalletPayment?.providerName ?? '')
                ..selection = TextSelection.fromPosition(
                  TextPosition(
                      offset: ewalletPayment?.providerName?.length ?? 0),
                ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                OutlinedButton.icon(
                  onPressed: () => onPickImage('ewallet'),
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
                  onPressed: () => onPickImageFromGallery('ewallet'),
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
