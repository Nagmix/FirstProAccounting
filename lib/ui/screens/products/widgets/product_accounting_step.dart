import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../data/models/inventory_cost_layer_model.dart';
import 'product_form_helpers.dart';

// ═══════════════════════════════════════════════════════════════════
//  Step 8 – المحاسبة
// ═══════════════════════════════════════════════════════════════════

class ProductAccountingStep extends StatelessWidget {
  // Controllers
  final TextEditingController taxRateController;

  // Values
  final int? selectedSalesAccountId;
  final int? selectedPurchaseAccountId;
  final int? selectedInventoryAccountId;
  final int? selectedCogsAccountId;
  final int? selectedVatAccountId;
  final CostingMethod costingMethod;
  final bool isEditMode;

  // Dropdown data
  final List<Map<String, dynamic>> revenueAccounts;
  final List<Map<String, dynamic>> costAccounts;
  final List<Map<String, dynamic>> assetAccounts;
  final List<Map<String, dynamic>> liabilityAccounts;

  // Callbacks
  final ValueChanged<int?> onSalesAccountChanged;
  final ValueChanged<int?> onPurchaseAccountChanged;
  final ValueChanged<int?> onInventoryAccountChanged;
  final ValueChanged<int?> onCogsAccountChanged;
  final ValueChanged<int?> onVatAccountChanged;
  final ValueChanged<CostingMethod> onCostingMethodChanged;

  const ProductAccountingStep({
    super.key,
    required this.taxRateController,
    required this.selectedSalesAccountId,
    required this.selectedPurchaseAccountId,
    required this.selectedInventoryAccountId,
    required this.selectedCogsAccountId,
    required this.selectedVatAccountId,
    required this.costingMethod,
    required this.isEditMode,
    required this.revenueAccounts,
    required this.costAccounts,
    required this.assetAccounts,
    required this.liabilityAccounts,
    required this.onSalesAccountChanged,
    required this.onPurchaseAccountChanged,
    required this.onInventoryAccountChanged,
    required this.onCogsAccountChanged,
    required this.onVatAccountChanged,
    required this.onCostingMethodChanged,
  });

  @override
  Widget build(BuildContext context) {
    final isLocked = false; // Allow editing accounts in edit mode
    final taxRate = double.tryParse(taxRateController.text) ?? 0.0;
    final showVatAccount = taxRate > 0;

    // Ensure selected IDs exist in their respective lists to avoid DropdownButton errors
    final validSalesAccountId = revenueAccounts.any((a) => a['id'] == selectedSalesAccountId)
        ? selectedSalesAccountId : null;
    final validPurchaseAccountId = costAccounts.any((a) => a['id'] == selectedPurchaseAccountId)
        ? selectedPurchaseAccountId : null;
    final validInventoryAccountId = assetAccounts.any((a) => a['id'] == selectedInventoryAccountId)
        ? selectedInventoryAccountId : null;
    final validCogsAccountId = costAccounts.any((a) => a['id'] == selectedCogsAccountId)
        ? selectedCogsAccountId : null;
    final validVatAccountId = liabilityAccounts.any((a) => a['id'] == selectedVatAccountId)
        ? selectedVatAccountId : null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const StepTitle(title: 'المحاسبة', icon: Icons.account_balance),

        if (isEditMode)
          Container(
            padding: const EdgeInsets.all(10),
            margin: const EdgeInsets.only(bottom: 12),
            decoration: BoxDecoration(
              color: AppColors.infoLight.withOpacity(0.5),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: AppColors.info.withOpacity(0.3)),
            ),
            child: Row(
              children: [
                const Icon(Icons.edit, size: 18, color: AppColors.info),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'يمكنك تعديل الحسابات المحاسبية إذا كانت غير صحيحة',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: AppColors.info,
                        ),
                  ),
                ),
              ],
            ),
          ),

        // حساب المبيعات
        DropdownButtonFormField<int>(
          value: validSalesAccountId,
          isDense: true,
          decoration: const InputDecoration(
            labelText: 'حساب المبيعات',
            prefixIcon: Icon(Icons.trending_up),
          ),
          items: revenueAccounts
              .map((a) => DropdownMenuItem<int>(
                    value: a['id'] as int,
                    child: Text(
                      '${a['name_ar'] ?? ''} (${a['account_code'] ?? ''})',
                      overflow: TextOverflow.ellipsis,
                    ),
                  ))
              .toList(),
          onChanged: isLocked ? null : (v) => onSalesAccountChanged(v),
        ),
        const SizedBox(height: 14),

        // حساب المشتريات
        DropdownButtonFormField<int>(
          value: validPurchaseAccountId,
          isDense: true,
          decoration: const InputDecoration(
            labelText: 'حساب المشتريات',
            prefixIcon: Icon(Icons.trending_down),
          ),
          items: costAccounts
              .map((a) => DropdownMenuItem<int>(
                    value: a['id'] as int,
                    child: Text(
                      '${a['name_ar'] ?? ''} (${a['account_code'] ?? ''})',
                      overflow: TextOverflow.ellipsis,
                    ),
                  ))
              .toList(),
          onChanged: isLocked ? null : (v) => onPurchaseAccountChanged(v),
        ),
        const SizedBox(height: 14),

        // حساب المخزون
        DropdownButtonFormField<int>(
          value: validInventoryAccountId,
          isDense: true,
          decoration: const InputDecoration(
            labelText: 'حساب المخزون',
            prefixIcon: Icon(Icons.warehouse),
          ),
          items: assetAccounts
              .map((a) => DropdownMenuItem<int>(
                    value: a['id'] as int,
                    child: Text(
                      '${a['name_ar'] ?? ''} (${a['account_code'] ?? ''})',
                      overflow: TextOverflow.ellipsis,
                    ),
                  ))
              .toList(),
          onChanged: isLocked ? null : (v) => onInventoryAccountChanged(v),
        ),
        const SizedBox(height: 14),

        // حساب تكلفة البضاعة المباعة (COGS)
        DropdownButtonFormField<int>(
          value: validCogsAccountId,
          isDense: true,
          decoration: const InputDecoration(
            labelText: 'حساب تكلفة البضاعة المباعة',
            prefixIcon: Icon(Icons.account_balance_wallet),
          ),
          items: costAccounts
              .map((a) => DropdownMenuItem<int>(
                    value: a['id'] as int,
                    child: Text(
                      '${a['name_ar'] ?? ''} (${a['account_code'] ?? ''})',
                      overflow: TextOverflow.ellipsis,
                    ),
                  ))
              .toList(),
          onChanged: isLocked ? null : (v) => onCogsAccountChanged(v),
        ),
        const SizedBox(height: 14),

        // طريقة احتساب التكلفة (W-07)
        DropdownButtonFormField<String>(
          value: costingMethod.value,
          isDense: true,
          decoration: const InputDecoration(
            labelText: 'طريقة احتساب التكلفة',
            prefixIcon: Icon(Icons.calculate),
          ),
          items: CostingMethod.values
              .map((m) => DropdownMenuItem<String>(
                    value: m.value,
                    child: Text(m.nameAr),
                  ))
              .toList(),
          onChanged: (v) {
            if (v == null) return;
            final method = CostingMethodExt.fromValue(v);
            if (method == CostingMethod.lifo) {
              showDialog(
                context: context,
                builder: (ctx) => AlertDialog(
                  icon: const Icon(Icons.warning, color: AppColors.warning, size: 40),
                  title: const Text('تنبيه'),
                  content: const Text(
                    'تنبيه: طريقة LIFO محظورة بموجب معايير IFRS (IAS 2). هذه الطريقة مسموحة فقط ضمن US GAAP. استخدامها قد يؤدي لقوائم مالية غير متوافقة مع المعايير الدولية.',
                  ),
                  actions: [
                    TextButton(
                      onPressed: () {
                        Navigator.of(ctx).pop();
                        onCostingMethodChanged(method);
                      },
                      child: const Text('فهمت، استمر'),
                    ),
                    TextButton(
                      onPressed: () {
                        Navigator.of(ctx).pop();
                        // Revert to previous costing method by notifying parent
                        // with the current (unchanged) value, which forces a rebuild
                        // and resets the dropdown visual state.
                        onCostingMethodChanged(costingMethod);
                      },
                      child: const Text('إلغاء'),
                    ),
                  ],
                ),
              );
            } else {
              onCostingMethodChanged(method);
            }
          },
        ),
        const SizedBox(height: 14),

        // حساب ضريبة القيمة المضافة (only show if tax > 0)
        if (showVatAccount) ...[
          DropdownButtonFormField<int>(
            value: validVatAccountId,
            isDense: true,
            decoration: const InputDecoration(
              labelText: 'حساب ضريبة القيمة المضافة',
              prefixIcon: Icon(Icons.receipt_long),
            ),
            items: liabilityAccounts
                .map((a) => DropdownMenuItem<int>(
                      value: a['id'] as int,
                      child: Text(
                        '${a['name_ar'] ?? ''} (${a['account_code'] ?? ''})',
                        overflow: TextOverflow.ellipsis,
                      ),
                    ))
                .toList(),
            onChanged: isLocked ? null : (v) => onVatAccountChanged(v),
          ),
          const SizedBox(height: 14),

          // VAT accounting info card
          Container(
            padding: const EdgeInsets.all(10),
            margin: const EdgeInsets.only(bottom: 12),
            decoration: BoxDecoration(
              color: AppColors.infoLight.withOpacity(0.5),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: AppColors.info.withOpacity(0.2)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.info_outline, size: 18, color: AppColors.info),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'محاسبة الضريبة',
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              fontWeight: FontWeight.w700,
                              color: AppColors.info,
                            ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  'البيع: مدين (العميل) ← دائن (المبيعات + الضريبة)',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: AppColors.info,
                      ),
                ),
                const SizedBox(height: 4),
                Text(
                  'الشراء: مدين (المشتريات + الضريبة) ← دائن (المورد)',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: AppColors.info,
                      ),
                ),
              ],
            ),
          ),
        ],

        const SizedBox(height: 40),
      ],
    );
  }
}
