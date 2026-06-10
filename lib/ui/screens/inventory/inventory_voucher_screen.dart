import 'package:flutter/material.dart';
import '../../../core/utils/money_helper.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/di/service_locator.dart';
import '../../../data/datasources/repositories/reference_data_repository.dart';
import '../../../data/datasources/repositories/product_repository.dart';
import '../../../data/datasources/services/stock_service.dart';

class InventoryVoucherScreen extends StatefulWidget {
  const InventoryVoucherScreen({super.key});

  @override
  State<InventoryVoucherScreen> createState() => _InventoryVoucherScreenState();
}

class _InventoryVoucherScreenState extends State<InventoryVoucherScreen> {
  List<Map<String, dynamic>> _vouchers = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadVouchers();
  }

  Future<void> _loadVouchers() async {
    setState(() => _isLoading = true);
    _vouchers = await locator<StockService>().getAllInventoryVouchers();
    setState(() => _isLoading = false);
  }

  Future<void> _deleteVoucher(int id) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('حذف سند الجرد'),
        content: const Text('هل أنت متأكد من حذف سند الجرد هذا؟'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('إلغاء')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: AppColors.error),
            child: const Text('حذف'),
          ),
        ],
      ),
    );
    if (!mounted) return;
    if (confirmed == true) {
      await locator<StockService>().deleteInventoryVoucher(id);
      if (!mounted) return;
      _loadVouchers();
    }
  }

  Future<void> _confirmVoucher(int id) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('تأكيد سند الجرد'),
        content:
            const Text('سيتم تعديل المخزون وإنشاء قيود محاسبية. هل أنت متأكد؟'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('إلغاء')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: AppColors.success),
            child: const Text('تأكيد'),
          ),
        ],
      ),
    );
    if (!mounted) return;
    if (confirmed == true) {
      await locator<StockService>().confirmInventoryVoucher(id);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('تم تأكيد سند الجرد وتعديل المخزون'),
            backgroundColor: AppColors.success),
      );
      _loadVouchers();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('سند الجرد'),
        ),
        body: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : _vouchers.isEmpty
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.fact_check,
                            size: 64, color: AppColors.textHint),
                        const SizedBox(height: 16),
                        Text('لا توجد سندات جرد',
                            style: theme.textTheme.titleMedium
                                ?.copyWith(color: AppColors.textSecondary)),
                      ],
                    ),
                  )
                : RefreshIndicator(
                    onRefresh: _loadVouchers,
                    child: ListView.builder(
                      padding: const EdgeInsets.all(16),
                      itemCount: _vouchers.length,
                      itemBuilder: (context, index) {
                        final v = _vouchers[index];
                        final isDraft = (v['status'] as String?) == 'draft';
                        final totalDiff =
                            MoneyHelper.readMoney(v['total_diff_value']);
                        final currency = (v['currency'] as String?) ?? 'YER';
                        final currencySymbol = currency == 'SAR'
                            ? 'ر.س'
                            : (currency == 'USD' ? r'$' : 'ر.ي');

                        return Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: Material(
                            color: isDark
                                ? AppColors.darkSurface
                                : AppColors.surface,
                            borderRadius: BorderRadius.circular(14),
                            elevation: 1,
                            shadowColor: isDark
                                ? Colors.black26
                                : AppColors.primary.withValues(alpha: 0.06),
                            child: Padding(
                              padding: const EdgeInsets.all(16),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Container(
                                        width: 42,
                                        height: 42,
                                        decoration: BoxDecoration(
                                          color: isDraft
                                              ? AppColors.warning
                                                  .withValues(alpha: 0.1)
                                              : AppColors.success
                                                  .withValues(alpha: 0.1),
                                          borderRadius:
                                              BorderRadius.circular(12),
                                        ),
                                        child: Icon(
                                          Icons.fact_check,
                                          color: isDraft
                                              ? AppColors.warning
                                              : AppColors.success,
                                          size: 20,
                                        ),
                                      ),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              'سند رقم: ${v['voucher_number'] ?? ''}',
                                              style: theme.textTheme.bodyMedium
                                                  ?.copyWith(
                                                fontWeight: FontWeight.w600,
                                                color: isDark
                                                    ? AppColors.darkTextPrimary
                                                    : AppColors.textPrimary,
                                              ),
                                            ),
                                            const SizedBox(height: 2),
                                            Text(
                                              v['warehouse_name'] ??
                                                  'بدون مستودع',
                                              style: theme.textTheme.bodySmall
                                                  ?.copyWith(
                                                color: isDark
                                                    ? AppColors
                                                        .darkTextSecondary
                                                    : AppColors.textSecondary,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 10, vertical: 4),
                                        decoration: BoxDecoration(
                                          color: isDraft
                                              ? AppColors.warning
                                                  .withValues(alpha: 0.1)
                                              : AppColors.success
                                                  .withValues(alpha: 0.1),
                                          borderRadius:
                                              BorderRadius.circular(8),
                                        ),
                                        child: Text(
                                          isDraft ? 'مسودة' : 'مؤكد',
                                          style: theme.textTheme.labelSmall
                                              ?.copyWith(
                                            color: isDraft
                                                ? AppColors.warning
                                                : AppColors.success,
                                            fontWeight: FontWeight.w700,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 12),
                                  const Divider(height: 1),
                                  const SizedBox(height: 8),
                                  Row(
                                    children: [
                                      Icon(Icons.calendar_today,
                                          size: 14, color: AppColors.textHint),
                                      const SizedBox(width: 4),
                                      Text(
                                        v['voucher_date'] ?? '',
                                        style: theme.textTheme.bodySmall
                                            ?.copyWith(
                                                color: AppColors.textSecondary),
                                      ),
                                      const Spacer(),
                                      Text(
                                        'فرق القيمة: ${totalDiff.toStringAsFixed(2)} $currencySymbol',
                                        style:
                                            theme.textTheme.bodySmall?.copyWith(
                                          color: totalDiff >= 0
                                              ? AppColors.success
                                              : AppColors.error,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ],
                                  ),
                                  if (isDraft) ...[
                                    const SizedBox(height: 12),
                                    Row(
                                      mainAxisAlignment: MainAxisAlignment.end,
                                      children: [
                                        TextButton.icon(
                                          onPressed: () =>
                                              _confirmVoucher(v['id'] as int),
                                          icon: const Icon(Icons.check_circle,
                                              size: 18),
                                          label: const Text('تأكيد'),
                                          style: TextButton.styleFrom(
                                              foregroundColor:
                                                  AppColors.success),
                                        ),
                                        const SizedBox(width: 8),
                                        TextButton.icon(
                                          onPressed: () =>
                                              _deleteVoucher(v['id'] as int),
                                          icon: const Icon(Icons.delete,
                                              size: 18),
                                          label: const Text('حذف'),
                                          style: TextButton.styleFrom(
                                              foregroundColor: AppColors.error),
                                        ),
                                      ],
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
        floatingActionButton: FloatingActionButton(
          onPressed: () => _showCreateVoucherDialog(),
          backgroundColor: AppColors.primary,
          child: const Icon(Icons.add, color: Colors.white),
        ),
      ),
    );
  }

  Future<void> _showCreateVoucherDialog() async {
    final warehouses =
        await locator<ReferenceDataRepository>().getAllWarehouses();
    if (!mounted) return;
    final products =
        await locator<ProductRepository>().getAllProducts(activeOnly: true);
    if (!mounted) return;
    int? selectedWarehouseId;
    DateTime selectedDate = DateTime.now();
    String selectedCurrency = 'YER';
    String notes = '';

    // Controllers for counted quantities
    final Map<int, TextEditingController> qtyControllers = {};
    for (final p in products) {
      qtyControllers[p['id'] as int] = TextEditingController(
        text:
            (p['current_stock'] as num?)?.toDouble().toStringAsFixed(0) ?? '0',
      );
    }

    await showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return Directionality(
              textDirection: TextDirection.rtl,
              child: AlertDialog(
                title: const Text('إنشاء سند جرد جديد'),
                content: SizedBox(
                  width: MediaQuery.of(context).size.width * 0.9,
                  height: MediaQuery.of(context).size.height * 0.8,
                  child: Column(
                    children: [
                      // Warehouse selector
                      DropdownButtonFormField<int>(
                        value: selectedWarehouseId,
                        decoration: const InputDecoration(
                          labelText: 'المستودع',
                          border: OutlineInputBorder(),
                        ),
                        items: [
                          const DropdownMenuItem(
                              value: null, child: Text('كل المستودعات')),
                          ...warehouses.map((w) => DropdownMenuItem(
                                value: w['id'] as int,
                                child: Text(w['name'] as String),
                              )),
                        ],
                        onChanged: (val) =>
                            setDialogState(() => selectedWarehouseId = val),
                      ),
                      const SizedBox(height: 12),

                      // Date
                      InkWell(
                        onTap: () async {
                          final picked = await showDatePicker(
                            context: context,
                            initialDate: selectedDate,
                            firstDate: DateTime(2020),
                            lastDate: DateTime(2030),
                          );
                          if (picked != null) {
                            setDialogState(() => selectedDate = picked);
                          }
                        },
                        child: InputDecorator(
                          decoration: const InputDecoration(
                            labelText: 'تاريخ السند',
                            border: OutlineInputBorder(),
                          ),
                          child: Text(
                              '${selectedDate.year}-${selectedDate.month.toString().padLeft(2, '0')}-${selectedDate.day.toString().padLeft(2, '0')}'),
                        ),
                      ),
                      const SizedBox(height: 12),

                      // Currency
                      DropdownButtonFormField<String>(
                        value: selectedCurrency,
                        decoration: const InputDecoration(
                          labelText: 'العملة',
                          border: OutlineInputBorder(),
                        ),
                        items: const [
                          DropdownMenuItem(value: 'YER', child: Text('ر.ي')),
                          DropdownMenuItem(value: 'SAR', child: Text('ر.س')),
                          DropdownMenuItem(value: 'USD', child: Text(r'$')),
                        ],
                        onChanged: (val) =>
                            setDialogState(() => selectedCurrency = val!),
                      ),
                      const SizedBox(height: 12),

                      // Notes
                      TextField(
                        decoration: const InputDecoration(
                          labelText: 'ملاحظات',
                          border: OutlineInputBorder(),
                        ),
                        onChanged: (val) => notes = val,
                      ),
                      const SizedBox(height: 12),

                      // Products list
                      Expanded(
                        child: ListView.builder(
                          itemCount: products.length,
                          itemBuilder: (context, idx) {
                            final p = products[idx];
                            final pid = p['id'] as int;
                            final systemQty =
                                (p['current_stock'] as num?)?.toDouble() ?? 0.0;
                            // ignore: unused_local_variable
                            final costPrice =
                                MoneyHelper.readMoney(p['cost_price']);

                            return Padding(
                              padding: const EdgeInsets.only(bottom: 8),
                              child: Row(
                                children: [
                                  Expanded(
                                    flex: 3,
                                    child: Text(
                                      p['name_ar'] as String,
                                      style:
                                          Theme.of(context).textTheme.bodySmall,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                  const SizedBox(width: 4),
                                  SizedBox(
                                    width: 60,
                                    child: Text(
                                        'ن: ${systemQty.toStringAsFixed(0)}',
                                        style: Theme.of(context)
                                            .textTheme
                                            .bodySmall),
                                  ),
                                  const SizedBox(width: 4),
                                  SizedBox(
                                    width: 70,
                                    child: TextField(
                                      controller: qtyControllers[pid],
                                      decoration: const InputDecoration(
                                        isDense: true,
                                        hintText: 'الكمية',
                                        border: OutlineInputBorder(),
                                        contentPadding: EdgeInsets.symmetric(
                                            horizontal: 8, vertical: 8),
                                      ),
                                      keyboardType: TextInputType.number,
                                      style:
                                          Theme.of(context).textTheme.bodySmall,
                                    ),
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                      ),
                    ],
                  ),
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(ctx),
                    child: const Text('إلغاء'),
                  ),
                  ElevatedButton(
                    onPressed: () async {
                      // Create voucher
                      // ignore: unused_local_variable
                      final now = DateTime.now().toIso8601String();
                      final voucherNumber =
                          'IV-${DateTime.now().millisecondsSinceEpoch.toString().substring(8)}';

                      // ignore: unused_local_variable
                      double totalDiffValue = 0.0;
                      final List<Map<String, dynamic>> items = [];

                      for (final p in products) {
                        final pid = p['id'] as int;
                        final systemQty =
                            (p['current_stock'] as num?)?.toDouble() ?? 0.0;
                        final costPrice =
                            MoneyHelper.readMoney(p['cost_price']);
                        final countedQty =
                            double.tryParse(qtyControllers[pid]?.text ?? '0') ??
                                0.0;
                        final difference = countedQty - systemQty;
                        final diffValue = difference * costPrice;
                        totalDiffValue += diffValue;

                        items.add({
                          'product_id': pid,
                          'system_quantity': systemQty,
                          'actual_quantity': countedQty,
                          'difference': difference,
                          'unit_cost': costPrice,
                        });
                      }

                      final navigator = Navigator.of(ctx);
                      final scaffoldMessenger = ScaffoldMessenger.of(context);
                      await locator<StockService>().insertInventoryVoucher({
                        'voucher_number': voucherNumber,
                        'warehouse_id': selectedWarehouseId,
                        'date':
                            '${selectedDate.year}-${selectedDate.month.toString().padLeft(2, '0')}-${selectedDate.day.toString().padLeft(2, '0')}',
                        'status': 'draft',
                        'currency': selectedCurrency,
                        'description': notes,
                      }, items);

                      if (!mounted) return;
                      navigator.pop();
                      scaffoldMessenger.showSnackBar(
                        const SnackBar(
                            content: Text('تم إنشاء سند الجرد بنجاح'),
                            backgroundColor: AppColors.success),
                      );
                      _loadVouchers();
                    },
                    style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        foregroundColor: Colors.white),
                    child: const Text('حفظ كمسودة'),
                  ),
                ],
              ),
            );
          },
        );
      },
    );

    // Dispose controllers
    for (final c in qtyControllers.values) {
      c.dispose();
    }
  }
}
