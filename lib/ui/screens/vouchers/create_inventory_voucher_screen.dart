import 'package:flutter/material.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/currency_formatter.dart';
import '../../../core/utils/money_helper.dart';
import '../../../core/di/service_locator.dart';
import '../../../data/datasources/repositories/reference_data_repository.dart';
import '../../../data/datasources/repositories/product_repository.dart';
import '../../../data/datasources/services/stock_service.dart';

class CreateInventoryVoucherScreen extends StatefulWidget {
  const CreateInventoryVoucherScreen({super.key});

  @override
  State<CreateInventoryVoucherScreen> createState() => _CreateInventoryVoucherScreenScreenState();
}

class _CreateInventoryVoucherScreenScreenState extends State<CreateInventoryVoucherScreen> {
  final _formKey = GlobalKey<FormState>();
  final _descriptionController = TextEditingController();
  DateTime _selectedDate = DateTime.now();
  int? _selectedWarehouseId;
  String _selectedCurrency = 'YER';
  bool _isSaving = false;

  List<Map<String, dynamic>> _warehouses = [];
  List<Map<String, dynamic>> _products = [];
  List<_InventoryVoucherItem> _items = [];

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  @override
  void dispose() {
    _descriptionController.dispose();
    for (final item in _items) {
      item.actualQuantityController.dispose();
      item.notesController.dispose();
    }
    super.dispose();
  }

  Future<void> _loadData() async {
    final warehouses = await locator<ReferenceDataRepository>().getAllWarehouses();
    final products = await locator<ProductRepository>().getAllProducts(activeOnly: true);
    if (mounted) {
      setState(() {
        _warehouses = warehouses;
        _products = products;
      });
    }
  }

  void _addItem() {
    setState(() {
      _items.add(_InventoryVoucherItem());
    });
  }

  void _removeItem(int index) {
    setState(() {
      _items[index].actualQuantityController.dispose();
      _items[index].notesController.dispose();
      _items.removeAt(index);
    });
  }

  void _onProductSelected(int index, int? productId) {
    if (productId == null) return;
    final product = _products.firstWhere((p) => p['id'] == productId);
    setState(() {
      _items[index].productId = productId;
      _items[index].productName = product['name_ar'] as String? ?? '';
      _items[index].systemQuantity = (product['current_stock'] as num?)?.toDouble() ?? 0.0;
      _items[index].unitCost = MoneyHelper.readMoney(product['cost_price']);
    });
  }

  void _updateDifference(int index) {
    final actual = double.tryParse(_items[index].actualQuantityController.text) ?? 0.0;
    setState(() {
      _items[index].actualQuantity = actual;
      _items[index].difference = actual - _items[index].systemQuantity;
    });
  }

  double get _totalValue {
    return _items.fold(0.0, (sum, item) => sum + (item.difference.abs() * item.unitCost));
  }

  Future<void> _saveVoucher() async {
    if (_items.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('يجب إضافة بند واحد على الأقل'), backgroundColor: AppColors.error),
      );
      return;
    }

    // Validate all items have product and actual quantity
    for (int i = 0; i < _items.length; i++) {
      if (_items[i].productId == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('يرجى اختيار المنتج في البند ${i + 1}'), backgroundColor: AppColors.error),
        );
        return;
      }
    }

    setState(() => _isSaving = true);

    try {
      final voucherNumber = await locator<StockService>().getNextInventoryVoucherNumber();
      final dateStr = '${_selectedDate.year}-${_selectedDate.month.toString().padLeft(2, '0')}-${_selectedDate.day.toString().padLeft(2, '0')}';

      final voucherMap = {
        'voucher_number': voucherNumber,
        'date': dateStr,
        'warehouse_id': _selectedWarehouseId,
        'description': _descriptionController.text.isEmpty ? null : _descriptionController.text,
        'currency': _selectedCurrency,
        'total_value': _totalValue,
        'status': 'approved',
      };

      final itemsList = _items.map((item) => {
        'product_id': item.productId,
        'system_quantity': item.systemQuantity,
        'actual_quantity': item.actualQuantity,
        'difference': item.difference,
        'unit_cost': item.unitCost,
        'total_value': item.difference.abs() * item.unitCost,
        'notes': item.notesController.text.isEmpty ? null : item.notesController.text,
      }).toList();

      await locator<StockService>().insertInventoryVoucher(voucherMap, itemsList);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('تم حفظ سند الجرد بنجاح'), backgroundColor: AppColors.success),
        );
        Navigator.pop(context, true);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('حدث خطأ أثناء الحفظ'), backgroundColor: AppColors.error),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
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
          title: const Text('سند جرد جديد'),
          actions: [
            TextButton.icon(
              onPressed: _isSaving ? null : _saveVoucher,
              icon: const Icon(Icons.save, color: Colors.white),
              label: const Text('حفظ', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
            ),
          ],
        ),
        body: _isSaving
            ? const Center(child: CircularProgressIndicator())
            : Form(
                key: _formKey,
                child: SingleChildScrollView(
                  padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewPadding.bottom + 80),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildHeaderSection(theme, isDark),
                      const SizedBox(height: 16),
                      _buildItemsSection(theme, isDark),
                      const SizedBox(height: 16),
                      _buildTotalsSection(theme, isDark),
                    ],
                  ),
                ),
              ),
      ),
    );
  }

  Widget _buildHeaderSection(ThemeData theme, bool isDark) {
    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkSurface : AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: isDark ? AppColors.darkBorder : AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.inventory, color: AppColors.primary, size: 20),
              const SizedBox(width: 8),
              Text('بيانات سند الجرد', style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700, color: AppColors.primary)),
            ],
          ),
          const SizedBox(height: 16),

          // Date picker
          InkWell(
            onTap: () async {
              final picked = await showDatePicker(
                context: context,
                initialDate: _selectedDate,
                firstDate: DateTime(2020),
                lastDate: DateTime.now().add(const Duration(days: 365)),
                locale: const Locale('ar'),
              );
              if (picked != null) setState(() => _selectedDate = picked);
            },
            child: InputDecorator(
              decoration: InputDecoration(
                labelText: 'التاريخ',
                prefixIcon: const Icon(Icons.calendar_today, size: 20),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              ),
              child: Text(
                '${_selectedDate.year}-${_selectedDate.month.toString().padLeft(2, '0')}-${_selectedDate.day.toString().padLeft(2, '0')}',
                style: theme.textTheme.bodyMedium,
              ),
            ),
          ),
          const SizedBox(height: 12),

          // Warehouse selector
          DropdownButtonFormField<int>(
            value: _selectedWarehouseId,
            decoration: InputDecoration(
              labelText: 'المخزن',
              prefixIcon: const Icon(Icons.warehouse, size: 20),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
            ),
            items: [
              const DropdownMenuItem(value: null, child: Text('اختر المخزن (اختياري)')),
              ..._warehouses.map((w) => DropdownMenuItem(
                value: w['id'] as int,
                child: Text(w['name'] as String? ?? ''),
              )),
            ],
            onChanged: (v) => setState(() => _selectedWarehouseId = v),
          ),
          const SizedBox(height: 12),

          // Currency selector
          DropdownButtonFormField<String>(
            value: _selectedCurrency,
            decoration: InputDecoration(
              labelText: 'العملة',
              prefixIcon: const Icon(Icons.attach_money, size: 20),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
            ),
            items: const [
              DropdownMenuItem(value: 'YER', child: Text('ريال يمني (ر.ي)')),
              DropdownMenuItem(value: 'SAR', child: Text('ريال سعودي (ر.س)')),
              DropdownMenuItem(value: 'USD', child: Text('دولار أمريكي (\$)')),
            ],
            onChanged: (v) => setState(() => _selectedCurrency = v ?? 'YER'),
          ),
          const SizedBox(height: 12),

          // Description
          TextFormField(
            controller: _descriptionController,
            decoration: InputDecoration(
              labelText: 'الوصف',
              prefixIcon: const Icon(Icons.description, size: 20),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
            ),
            maxLines: 2,
          ),
        ],
      ),
    );
  }

  Widget _buildItemsSection(ThemeData theme, bool isDark) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkSurface : AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: isDark ? AppColors.darkBorder : AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Icon(Icons.list_alt, color: AppColors.primary, size: 20),
                  const SizedBox(width: 8),
                  Text('بنود السند', style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700, color: AppColors.primary)),
                ],
              ),
              TextButton.icon(
                onPressed: _addItem,
                icon: const Icon(Icons.add, size: 18),
                label: const Text('إضافة منتج'),
                style: TextButton.styleFrom(foregroundColor: AppColors.primary),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (_items.isEmpty)
            Padding(
              padding: const EdgeInsets.all(24),
              child: Center(
                child: Column(
                  children: [
                    Icon(Icons.add_shopping_cart, size: 48, color: AppColors.textHint.withOpacity(0.5)),
                    const SizedBox(height: 8),
                    Text('لم تتم إضافة منتجات بعد', style: theme.textTheme.bodyMedium?.copyWith(color: AppColors.textHint)),
                  ],
                ),
              ),
            )
          else
            ..._items.asMap().entries.map((entry) {
              final index = entry.key;
              final item = entry.value;
              return _buildItemCard(index, item, theme, isDark);
            }),
        ],
      ),
    );
  }

  Widget _buildItemCard(int index, _InventoryVoucherItem item, ThemeData theme, bool isDark) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkSurfaceVariant.withOpacity(0.3) : AppColors.surfaceVariant.withOpacity(0.5),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: isDark ? AppColors.darkBorder : AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
              Text('بند ${index + 1}', style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w700)),
              IconButton(
                onPressed: () => _removeItem(index),
                icon: const Icon(Icons.delete_outline, color: AppColors.error, size: 20),
                constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                padding: EdgeInsets.zero,
              ),
            ],
          ),
          const SizedBox(height: 8),

          // Product selector
          DropdownButtonFormField<int>(
            value: item.productId,
            decoration: InputDecoration(
              labelText: 'المنتج',
              isDense: true,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
            ),
            items: _products.map((p) => DropdownMenuItem(
              value: p['id'] as int,
              child: Text(p['name_ar'] as String? ?? '', overflow: TextOverflow.ellipsis),
            )).toList(),
            onChanged: (v) => _onProductSelected(index, v),
          ),
          const SizedBox(height: 8),

          // System quantity (auto-filled, read-only)
          Row(
            children: [
              Expanded(
                child: InputDecorator(
                  decoration: InputDecoration(
                    labelText: 'الكمية النظامية',
                    isDense: true,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                    filled: true,
                    fillColor: isDark ? AppColors.darkSurfaceVariant : AppColors.surfaceVariant,
                  ),
                  child: Text(item.systemQuantity.toStringAsFixed(2), style: theme.textTheme.bodyMedium),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TextFormField(
                  controller: item.actualQuantityController,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: InputDecoration(
                    labelText: 'الكمية الفعلية',
                    isDense: true,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  onChanged: (_) => _updateDifference(index),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),

          // Difference & unit cost
          Row(
            children: [
              Expanded(
                child: InputDecorator(
                  decoration: InputDecoration(
                    labelText: 'الفرق',
                    isDense: true,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                    filled: true,
                    fillColor: isDark ? AppColors.darkSurfaceVariant : AppColors.surfaceVariant,
                  ),
                  child: Text(
                    '${item.difference > 0 ? '+' : ''}${item.difference.toStringAsFixed(2)}',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: item.difference > 0 ? AppColors.success : (item.difference < 0 ? AppColors.error : null),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: InputDecorator(
                  decoration: InputDecoration(
                    labelText: 'تكلفة الوحدة',
                    isDense: true,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                    filled: true,
                    fillColor: isDark ? AppColors.darkSurfaceVariant : AppColors.surfaceVariant,
                  ),
                  child: Text(item.unitCost.toStringAsFixed(2), style: theme.textTheme.bodyMedium),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),

          // Total value for this item
          InputDecorator(
            decoration: InputDecoration(
              labelText: 'القيمة الإجمالية',
              isDense: true,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
              filled: true,
              fillColor: isDark ? AppColors.darkSurfaceVariant : AppColors.surfaceVariant,
            ),
            child: Text(
              CurrencyFormatter.format(item.difference.abs() * item.unitCost),
              style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w700, color: AppColors.primary),
            ),
          ),
          const SizedBox(height: 8),

          // Notes
          TextFormField(
            controller: item.notesController,
            decoration: InputDecoration(
              labelText: 'ملاحظات',
              isDense: true,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTotalsSection(ThemeData theme, bool isDark) {
    String currencySymbol;
    switch (_selectedCurrency) {
      case 'SAR':
        currencySymbol = 'ر.س';
        break;
      case 'USD':
        currencySymbol = r'$';
        break;
      default:
        currencySymbol = 'ر.ي';
    }

    final increaseItems = _items.where((i) => i.difference > 0).toList();
    final decreaseItems = _items.where((i) => i.difference < 0).toList();
    final totalIncrease = increaseItems.fold(0.0, (sum, i) => sum + (i.difference * i.unitCost));
    final totalDecrease = decreaseItems.fold(0.0, (sum, i) => sum + (i.difference.abs() * i.unitCost));

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [AppColors.primary.withOpacity(0.08), AppColors.secondary.withOpacity(0.08)],
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.primary.withOpacity(0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.calculate, color: AppColors.primary, size: 20),
              const SizedBox(width: 8),
              Text('ملخص', style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700, color: AppColors.primary)),
            ],
          ),
          const SizedBox(height: 12),
          _buildSummaryRow(theme, 'عدد البنود', '${_items.length}'),
          if (increaseItems.isNotEmpty) ...[
            const SizedBox(height: 4),
            _buildSummaryRow(theme, 'زيادة مخزون', CurrencyFormatter.format(totalIncrease, symbol: currencySymbol), color: AppColors.success),
          ],
          if (decreaseItems.isNotEmpty) ...[
            const SizedBox(height: 4),
            _buildSummaryRow(theme, 'نقص مخزون', CurrencyFormatter.format(totalDecrease, symbol: currencySymbol), color: AppColors.error),
          ],
          const Divider(height: 16),
          _buildSummaryRow(theme, 'القيمة الإجمالية', CurrencyFormatter.format(_totalValue, symbol: currencySymbol), isBold: true, color: AppColors.primary),
        ],
      ),
    );
  }

  Widget _buildSummaryRow(ThemeData theme, String label, String value, {bool isBold = false, Color? color}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: theme.textTheme.bodyMedium?.copyWith(fontWeight: isBold ? FontWeight.w700 : FontWeight.w500)),
        Text(value, style: theme.textTheme.bodyMedium?.copyWith(fontWeight: isBold ? FontWeight.w800 : FontWeight.w600, color: color)),
      ],
    );
  }
}

class _InventoryVoucherItem {
  int? productId;
  String productName = '';
  double systemQuantity = 0.0;
  double actualQuantity = 0.0;
  double difference = 0.0;
  double unitCost = 0.0;
  TextEditingController actualQuantityController = TextEditingController();
  TextEditingController notesController = TextEditingController();
}
