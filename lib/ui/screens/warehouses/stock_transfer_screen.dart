import 'package:flutter/material.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/di/service_locator.dart';
import '../../../data/datasources/repositories/reference_data_repository.dart';
import '../../../data/datasources/repositories/product_repository.dart';
import '../../../data/datasources/services/stock_service.dart';

/// شاشة التحويل المخزني - نقل المنتجات بين المستودعات
class StockTransferScreen extends StatefulWidget {
  const StockTransferScreen({super.key});

  @override
  State<StockTransferScreen> createState() => _StockTransferScreenState();
}

class _StockTransferScreenState extends State<StockTransferScreen> {
  List<Map<String, dynamic>> _warehouses = [];
  List<Map<String, dynamic>> _products = [];
  List<Map<String, dynamic>> _transfers = [];
  bool _isLoading = true;
  bool _isSaving = false;

  int? _fromWarehouseId;
  int? _toWarehouseId;
  int? _selectedProductId;
  final _quantityController = TextEditingController();
  final _notesController = TextEditingController();
  final _searchController = TextEditingController();
  String _productSearchQuery = '';
  bool _showProductSearch = false;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  @override
  void dispose() {
    _quantityController.dispose();
    _notesController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    final warehouses =
        await locator<ReferenceDataRepository>().getAllWarehouses();
    if (!mounted) return;
    final products =
        await locator<ProductRepository>().getAllProducts(activeOnly: true);
    if (!mounted) return;
    final transfers = await locator<StockService>().getAllStockTransfers();
    if (!mounted) return;

    setState(() {
      _warehouses = warehouses;
      _products = products;
      _transfers = transfers;
      _isLoading = false;
    });
  }

  List<Map<String, dynamic>> get _filteredProducts {
    if (_productSearchQuery.isEmpty) return _products;
    final q = _productSearchQuery.toLowerCase();
    return _products.where((p) {
      final nameAr = (p['name_ar'] as String? ?? '').toLowerCase();
      final barcode = (p['barcode'] as String? ?? '').toLowerCase();
      return nameAr.contains(q) || barcode.contains(q);
    }).toList();
  }

  String? _getProductName(int? id) {
    if (id == null) return '';
    final product = _products.where((p) => p['id'] == id).toList();
    return product.isNotEmpty ? product.first['name_ar'] as String : '';
  }

  Future<void> _submitTransfer() async {
    if (_fromWarehouseId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('يرجى اختيار مخزن المصدر'),
            backgroundColor: AppColors.warning),
      );
      return;
    }
    if (_toWarehouseId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('يرجى اختيار مخزن الوجهة'),
            backgroundColor: AppColors.warning),
      );
      return;
    }
    if (_fromWarehouseId == _toWarehouseId) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('لا يمكن التحويل لنفس المخزن'),
            backgroundColor: AppColors.warning),
      );
      return;
    }
    if (_selectedProductId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('يرجى اختيار المنتج'),
            backgroundColor: AppColors.warning),
      );
      return;
    }
    final quantity = double.tryParse(_quantityController.text) ?? 0;
    if (quantity <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('يرجى إدخال كمية صحيحة'),
            backgroundColor: AppColors.warning),
      );
      return;
    }

    // التحقق من الكمية المتاحة
    // Check warehouse-specific stock if source warehouse is selected
    if (_fromWarehouseId != null) {
      final scaffoldMessenger = ScaffoldMessenger.of(context);
      // Query stock in the specific source warehouse
      final warehouseStock = await locator<ProductRepository>()
          .getProductStockInWarehouse(_selectedProductId!, _fromWarehouseId!);
      if (!mounted) return;
      if (warehouseStock == null) {
        scaffoldMessenger.showSnackBar(
          const SnackBar(
              content: Text('المنتج غير موجود في مخزن المصدر'),
              backgroundColor: AppColors.warning),
        );
        return;
      }
      if (quantity > warehouseStock) {
        scaffoldMessenger.showSnackBar(
          SnackBar(
              content: Text('الكمية المتاحة في المخزن $warehouseStock فقط'),
              backgroundColor: AppColors.warning),
        );
        return;
      }
    } else {
      // Fallback: check total stock (no specific warehouse selected)
      final sourceProduct =
          _products.where((p) => p['id'] == _selectedProductId).toList();
      if (sourceProduct.isNotEmpty) {
        final currentStock =
            (sourceProduct.first['current_stock'] as num?)?.toDouble() ?? 0.0;
        if (quantity > currentStock) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
                content:
                    Text('الكمية المتاحة $currentStock فقط (إجمالي المخزون)'),
                backgroundColor: AppColors.warning),
          );
          return;
        }
      }
    }

    setState(() => _isSaving = true);

    final now = DateTime.now();

    // توليد رقم التحويل
    final existingTransfers =
        await locator<StockService>().getAllStockTransfers();
    final transferNumber =
        'ST-${(existingTransfers.length + 1).toString().padLeft(4, '0')}';

    final transferMap = {
      'transfer_number': transferNumber,
      'from_warehouse_id': _fromWarehouseId,
      'to_warehouse_id': _toWarehouseId,
      'product_id': _selectedProductId,
      'quantity': quantity,
      'notes': _notesController.text.trim().isEmpty
          ? null
          : _notesController.text.trim(),
      'date': now.toIso8601String().substring(0, 10),
      'created_at': now.toIso8601String(),
    };

    await locator<StockService>().insertStockTransfer(transferMap);

    if (mounted) {
      setState(() {
        _isSaving = false;
        _fromWarehouseId = null;
        _toWarehouseId = null;
        _selectedProductId = null;
        _quantityController.clear();
        _notesController.clear();
        _productSearchQuery = '';
        _searchController.clear();
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('تم التحويل بنجاح'),
            backgroundColor: AppColors.success),
      );

      _loadData();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: const Text('تحويل مخزني'),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // بطاقة التحويل
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'تحويل جديد',
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w700,
                              color: AppColors.primary,
                            ),
                          ),
                          const SizedBox(height: 16),

                          // من مخزن
                          _buildWarehouseDropdown(
                            label: 'من مخزن',
                            value: _fromWarehouseId,
                            items: _warehouses,
                            onChanged: (v) =>
                                setState(() => _fromWarehouseId = v),
                            isDark: isDark,
                          ),
                          const SizedBox(height: 12),

                          // أيقونة التحويل
                          Center(
                            child: Container(
                              width: 40,
                              height: 40,
                              decoration: BoxDecoration(
                                color: AppColors.primary.withValues(alpha: 0.1),
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(
                                Icons.swap_vert,
                                color: AppColors.primary,
                              ),
                            ),
                          ),
                          const SizedBox(height: 12),

                          // إلى مخزن
                          _buildWarehouseDropdown(
                            label: 'إلى مخزن',
                            value: _toWarehouseId,
                            items: _warehouses,
                            onChanged: (v) =>
                                setState(() => _toWarehouseId = v),
                            isDark: isDark,
                          ),
                          const SizedBox(height: 16),

                          // اختيار المنتج
                          Text(
                            'المنتج',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: AppColors.primary,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 6),
                          InkWell(
                            onTap: () => setState(
                                () => _showProductSearch = !_showProductSearch),
                            borderRadius: BorderRadius.circular(12),
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 14, vertical: 12),
                              decoration: BoxDecoration(
                                color: isDark
                                    ? AppColors.darkSurfaceVariant
                                    : AppColors.surfaceVariant,
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: _selectedProductId != null
                                      ? AppColors.primary
                                      : AppColors.border,
                                ),
                              ),
                              child: Row(
                                children: [
                                  Icon(
                                    Icons.inventory_2,
                                    size: 20,
                                    color: _selectedProductId != null
                                        ? AppColors.primary
                                        : AppColors.textHint,
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Text(
                                      _selectedProductId != null
                                          ? _getProductName(_selectedProductId)!
                                          : 'اختر المنتج',
                                      style:
                                          theme.textTheme.bodyMedium?.copyWith(
                                        color: _selectedProductId != null
                                            ? null
                                            : AppColors.textHint,
                                      ),
                                    ),
                                  ),
                                  Icon(
                                    _showProductSearch
                                        ? Icons.expand_less
                                        : Icons.expand_more,
                                    color: AppColors.textHint,
                                  ),
                                ],
                              ),
                            ),
                          ),

                          // بحث واختيار المنتج
                          if (_showProductSearch) ...[
                            const SizedBox(height: 8),
                            TextField(
                              controller: _searchController,
                              decoration: InputDecoration(
                                hintText: 'بحث عن منتج...',
                                prefixIcon: const Icon(Icons.search, size: 20),
                                suffixIcon: _productSearchQuery.isNotEmpty
                                    ? IconButton(
                                        icon: const Icon(Icons.clear, size: 18),
                                        onPressed: () {
                                          _searchController.clear();
                                          setState(
                                              () => _productSearchQuery = '');
                                        },
                                      )
                                    : null,
                                isDense: true,
                                contentPadding: const EdgeInsets.symmetric(
                                    horizontal: 12, vertical: 8),
                              ),
                              onChanged: (v) =>
                                  setState(() => _productSearchQuery = v),
                            ),
                            const SizedBox(height: 4),
                            Container(
                              constraints: const BoxConstraints(maxHeight: 200),
                              decoration: BoxDecoration(
                                color: isDark
                                    ? AppColors.darkSurface
                                    : AppColors.surface,
                                border: Border.all(color: AppColors.border),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: ListView.builder(
                                shrinkWrap: true,
                                itemCount: _filteredProducts.length,
                                itemBuilder: (context, index) {
                                  final product = _filteredProducts[index];
                                  final isSelected =
                                      product['id'] == _selectedProductId;
                                  final stock =
                                      (product['current_stock'] as num?)
                                              ?.toDouble() ??
                                          0.0;
                                  final productWarehouseId =
                                      product['warehouse_id'] as int?;
                                  // Show warehouse-specific stock if source warehouse is selected
                                  final isInSourceWarehouse =
                                      _fromWarehouseId == null ||
                                          productWarehouseId ==
                                              _fromWarehouseId;
                                  return ListTile(
                                    dense: true,
                                    selected: isSelected,
                                    selectedTileColor: AppColors.primary
                                        .withValues(alpha: 0.08),
                                    leading: Icon(
                                      isSelected
                                          ? Icons.check_circle
                                          : Icons.circle_outlined,
                                      color: isSelected
                                          ? AppColors.primary
                                          : AppColors.textHint,
                                      size: 20,
                                    ),
                                    title: Text(
                                      product['name_ar'] as String? ?? '',
                                      style: theme.textTheme.bodySmall,
                                    ),
                                    trailing: Text(
                                      'المخزون: $stock${!isInSourceWarehouse ? " *" : ""}',
                                      style:
                                          theme.textTheme.labelSmall?.copyWith(
                                        color: stock > 0
                                            ? AppColors.success
                                            : AppColors.error,
                                      ),
                                    ),
                                    onTap: () {
                                      setState(() {
                                        _selectedProductId =
                                            product['id'] as int;
                                        _showProductSearch = false;
                                        _productSearchQuery = '';
                                        _searchController.clear();
                                      });
                                    },
                                  );
                                },
                              ),
                            ),
                          ],

                          const SizedBox(height: 16),

                          // الكمية
                          TextFormField(
                            controller: _quantityController,
                            keyboardType: const TextInputType.numberWithOptions(
                                decimal: true),
                            decoration: const InputDecoration(
                              labelText: 'الكمية',
                              prefixIcon: Icon(Icons.numbers),
                            ),
                          ),
                          const SizedBox(height: 12),

                          // ملاحظات
                          TextFormField(
                            controller: _notesController,
                            maxLines: 2,
                            decoration: const InputDecoration(
                              labelText: 'ملاحظات (اختياري)',
                              prefixIcon: Icon(Icons.note),
                            ),
                          ),
                          const SizedBox(height: 20),

                          // زر التحويل
                          SizedBox(
                            width: double.infinity,
                            child: ElevatedButton.icon(
                              onPressed: _isSaving ? null : _submitTransfer,
                              icon: _isSaving
                                  ? const SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                          strokeWidth: 2, color: Colors.white),
                                    )
                                  : const Icon(Icons.swap_horiz, size: 22),
                              label:
                                  Text(_isSaving ? 'جاري التحويل...' : 'تحويل'),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: AppColors.primary,
                                foregroundColor: Colors.white,
                                padding:
                                    const EdgeInsets.symmetric(vertical: 14),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                  const SizedBox(height: 24),

                  // التحويلات الأخيرة
                  Text(
                    'التحويلات الأخيرة',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: AppColors.primary,
                    ),
                  ),
                  const SizedBox(height: 8),
                  if (_transfers.isEmpty)
                    Center(
                      child: Padding(
                        padding: const EdgeInsets.all(32),
                        child: Column(
                          children: [
                            Icon(Icons.swap_horiz,
                                size: 48, color: AppColors.textHint),
                            const SizedBox(height: 8),
                            Text(
                              'لا توجد تحويلات',
                              style: theme.textTheme.bodyMedium
                                  ?.copyWith(color: AppColors.textHint),
                            ),
                          ],
                        ),
                      ),
                    )
                  else
                    ..._transfers.take(20).map((transfer) => _TransferCard(
                          transfer: transfer,
                          isDark: isDark,
                        )),
                ],
              ),
            ),
    );
  }

  Widget _buildWarehouseDropdown({
    required String label,
    required int? value,
    required List<Map<String, dynamic>> items,
    required ValueChanged<int?> onChanged,
    required bool isDark,
  }) {
    final theme = Theme.of(context);
    return DropdownButtonFormField<int>(
      value: value,
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: const Icon(Icons.warehouse, size: 20),
        filled: true,
        fillColor:
            isDark ? AppColors.darkSurfaceVariant : AppColors.surfaceVariant,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
      ),
      items: items.map((w) {
        return DropdownMenuItem<int>(
          value: w['id'] as int,
          child: Text(w['name'] as String, style: theme.textTheme.bodyMedium),
        );
      }).toList(),
      onChanged: onChanged,
    );
  }
}

class _TransferCard extends StatelessWidget {
  const _TransferCard({
    required this.transfer,
    required this.isDark,
  });

  final Map<String, dynamic> transfer;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final fromName = transfer['from_warehouse_name'] as String? ?? 'غير محدد';
    final toName = transfer['to_warehouse_name'] as String? ?? 'غير محدد';
    final productName = transfer['product_name'] as String? ?? 'غير محدد';
    final quantity = (transfer['quantity'] as num?)?.toDouble() ?? 0.0;
    final transferNumber = transfer['transfer_number'] as String? ?? '';

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: AppColors.info.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child:
                  const Icon(Icons.swap_horiz, color: AppColors.info, size: 22),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    productName,
                    style: theme.textTheme.bodyMedium
                        ?.copyWith(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '$fromName ← $toName',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: isDark
                          ? AppColors.darkTextSecondary
                          : AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  '$quantity',
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: AppColors.primary,
                  ),
                ),
                Text(
                  transferNumber,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: isDark
                        ? AppColors.darkTextSecondary
                        : AppColors.textHint,
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
