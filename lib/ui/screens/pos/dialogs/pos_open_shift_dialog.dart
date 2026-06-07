import 'package:flutter/material.dart';

import '../../../../core/constants/app_constants.dart';
import '../../../../core/extensions/context_extensions.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/di/service_locator.dart';
import '../../../../core/viewmodels/pos_viewmodel.dart';
import '../../../../data/datasources/services/cash_box_service.dart';
import '../../../../data/datasources/services/shift_service.dart';
import '../../../../data/datasources/services/report_service.dart';

/// Opens the "Open Shift" bottom sheet dialog.
Future<void> showOpenShiftDialog(BuildContext context, PosViewModel vm) async {
  final cashBoxes = await locator<CashBoxService>().getAllCashBoxes();
  if (cashBoxes.isEmpty) {
    if (context.mounted) {
      context.showErrorSnackBar('لا توجد صناديق نقدية. أضف صندوقاً أولاً من الإعدادات.');
    }
    return;
  }

  int? selectedCashBoxId = cashBoxes.first['id'] as int?;
  final amountController = TextEditingController(text: '0');
  final cashierNameController = TextEditingController(text: vm.cashierName);
  final notesController = TextEditingController();

  await showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    isDismissible: false,
    enableDrag: false,
    builder: (ctx) => Directionality(
      textDirection: TextDirection.rtl,
      child: Padding(
        padding: EdgeInsets.only(
          left: 20,
          right: 20,
          top: 20,
          bottom: MediaQuery.of(ctx).viewInsets.bottom + MediaQuery.of(ctx).viewPadding.bottom + 20,
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    color: AppColors.divider,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: AppColors.success.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(Icons.lock_open, color: AppColors.success, size: 24),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    'فتح وردية جديدة',
                    style: context.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),

              // ── Cashier name ─────────────────────────────────
              Text('اسم الكاشير', style: context.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
              const SizedBox(height: 6),
              TextField(
                controller: cashierNameController,
                textInputAction: TextInputAction.next,
                decoration: InputDecoration(
                  hintText: 'أدخل اسم الكاشير',
                  prefixIcon: const Icon(Icons.person, size: 20),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                ),
              ),
              const SizedBox(height: 16),

              // ── Cash box selector ────────────────────────────
              Text('الصندوق النقدي', style: context.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
              const SizedBox(height: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                decoration: BoxDecoration(
                  border: Border.all(color: AppColors.border),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<int>(
                    value: selectedCashBoxId,
                    isExpanded: true,
                    items: cashBoxes.map<DropdownMenuItem<int>>((cb) {
                      final id = cb['id'] as int;
                      final name = cb['name']?.toString() ?? '';
                      final type = cb['type']?.toString() ?? 'cash_box';
                      final currency = cb['currency']?.toString() ?? 'YER';
                      final typeLabel = type == 'bank' ? 'بنك' : 'صندوق';
                      return DropdownMenuItem<int>(
                        value: id,
                        child: Text('$name ($typeLabel - $currency)'),
                      );
                    }).toList(),
                    onChanged: (val) {
                      if (val != null) selectedCashBoxId = val;
                    },
                  ),
                ),
              ),
              const SizedBox(height: 16),

              // ── Opening amount ───────────────────────────────
              Text('مبلغ الافتتاح', style: context.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
              const SizedBox(height: 6),
              TextField(
                controller: amountController,
                keyboardType: TextInputType.number,
                textInputAction: TextInputAction.done,
                decoration: InputDecoration(
                  hintText: 'أدخل مبلغ الافتتاح',
                  suffixText: AppConstants.currency,
                  prefixIcon: const Icon(Icons.account_balance_wallet, size: 20),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                ),
              ),
              const SizedBox(height: 16),

              // ── Notes ────────────────────────────────────────
              Text('ملاحظات (اختياري)', style: context.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
              const SizedBox(height: 6),
              TextField(
                controller: notesController,
                maxLines: 2,
                textInputAction: TextInputAction.done,
                decoration: InputDecoration(
                  hintText: 'ملاحظات...',
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                ),
              ),
              const SizedBox(height: 20),

              // ── Open shift button ────────────────────────────
              SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton(
                  onPressed: () async {
                    if (selectedCashBoxId == null) {
                      ScaffoldMessenger.of(ctx).showSnackBar(
                        const SnackBar(content: Text('اختر صندوقاً نقدیاً'), backgroundColor: AppColors.warning),
                      );
                      return;
                    }
                    if (cashierNameController.text.trim().isEmpty) {
                      ScaffoldMessenger.of(ctx).showSnackBar(
                        const SnackBar(content: Text('أدخل اسم الكاشير'), backgroundColor: AppColors.warning),
                      );
                      return;
                    }

                    final existingShift = await locator<ShiftService>().getActiveShift(selectedCashBoxId!);
                    if (existingShift != null) {
                      if (context.mounted) {
                        ScaffoldMessenger.of(ctx).showSnackBar(
                          const SnackBar(content: Text('يوجد وردية مفتوحة لهذا الصندوق بالفعل'), backgroundColor: AppColors.warning),
                        );
                      }
                      return;
                    }

                    final cashierName = cashierNameController.text.trim();
                    final openingAmount = double.tryParse(amountController.text) ?? 0.0;
                    final now = DateTime.now();

                    // Get next shift number
                    final reportService = locator<ReportService>();
                    final shiftNum = await reportService.getShiftCountForDate(now) + 1;

                    final shiftMap = {
                      'shift_number': shiftNum,
                      'cashier_id': null,
                      'cashier_name': cashierName,
                      'cash_box_id': selectedCashBoxId,
                      'opening_amount': openingAmount,
                      'closing_amount': null,
                      'expected_amount': openingAmount,
                      'difference': null,
                      'status': 'open',
                      'opened_at': now.toIso8601String(),
                      'closed_at': null,
                      'notes': notesController.text.isEmpty ? null : notesController.text,
                      'total_sales': 0.0,
                      'total_returns': 0.0,
                      'total_discounts': 0.0,
                      'transaction_count': 0,
                      'currency': vm.selectedCurrency,
                      'created_at': now.toIso8601String(),
                      'updated_at': now.toIso8601String(),
                    };
                    await vm.openShift(shiftMap);

                    if (!context.mounted) return;
                    Navigator.pop(ctx);
                    context.showSuccessSnackBar('تم فتح الوردية $shiftNum بنجاح');
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.success,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                  child: const Text('فتح الوردية', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );

  amountController.dispose();
  cashierNameController.dispose();
  notesController.dispose();
}
