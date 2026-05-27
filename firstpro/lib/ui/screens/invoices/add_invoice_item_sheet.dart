import 'package:flutter/material.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/extensions/context_extensions.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/currency_formatter.dart';
import '../../../data/datasources/database_helper.dart';
import '../../../data/models/invoice_item_model.dart';
import '../../../data/models/product_model.dart';
import '../../widgets/barcode_scanner_screen.dart';

class AddInvoiceItemSheet extends StatefulWidget {
  final int? warehouseId;
  final String invoiceType; // 'sale' or 'purchase'
  const AddInvoiceItemSheet({super.key, this.warehouseId, this.invoiceType = 'sale'});

  @override
  State<AddInvoiceItemSheet> createState() => _AddInvoiceItemSheetState();
}

class _AddInvoiceItemSheetState extends State<AddInvoiceItemSheet> {
  final _quantityController = TextEditingController(text: '1');
  final _priceController = TextEditingController();
  final _discountController = TextEditingController();
  final _notesController = TextEditingController();
  final _searchController = TextEditingController();

  Product? _selectedProduct;
  List<Product> _searchResults = [];
  bool _isSearching = false;

  // Unit selection
  List<Map<String, dynamic>> _availableUnits = [];
  Map<String, dynamic>? _selectedUnit;
  bool _loadingUnits = false;

  double get _quantity => double.tryParse(_quantityController.text) ?? 1;
  double get _unitPrice => double.tryParse(_priceController.text) ?? 0;
  double get _discount => double.tryParse(_discountController.text) ?? 0;
  double get _total => (_quantity * _unitPrice) - _discount;
  double get _conversionFactor => (_selectedUnit?['conversion_factor'] as num?)?.toDouble() ?? 1.0;
  double get _baseQuantity => _quantity * _conversionFactor;
  String get _unitName => (_selectedUnit?['unit_name'] as String?) ?? '';

  @override
  void initState() {
    super.initState();
    _searchProducts('');
  }

  @override
  void dispose() {
    _quantityController.dispose();
    _priceController.dispose();
    _discountController.dispose();
    _notesController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _searchProducts(String query) async {
    setState(() => _isSearching = true);
    final db = DatabaseHelper();
    List<Map<String, dynamic>> maps;
    if (query.isEmpty) {
      maps = await db.getAllProducts(activeOnly: true);
    } else {
      maps = await db.searchProducts(query, warehouseId: widget.warehouseId);
    }
    if (!mounted) return;
    setState(() {
      _searchResults = maps.map((m) => Product.fromMap(m)).toList();
      _isSearching = false;
    });
  }

  Future<void> _loadUnitsForProduct(int productId) async {
    setState(() => _loadingUnits = true);
    final db = DatabaseHelper();
    final units = await db.getAvailableUnitsForProduct(productId);
    if (!mounted) return;
    setState(() {
      _availableUnits = units;
      _loadingUnits = false;
      // Auto-select default unit based on invoice type
      if (units.isNotEmpty) {
        if (widget.invoiceType == 'purchase' && units.length > 1) {
          // For purchase, prefer non-base unit (e.g., carton) if available
          final nonBase = units.where((u) => u['is_base'] == 0).toList();
          _selectedUnit = nonBase.isNotEmpty ? nonBase.first : units.first;
        } else {
          _selectedUnit = units.first;
        }
        // Use cost_price for purchase invoices, sell_price for sale invoices
        if (widget.invoiceType == 'purchase') {
          _priceController.text = ((_selectedUnit?['cost_price'] as num?)?.toDouble() ?? 0).toStringAsFixed(2);
        } else {
          _priceController.text = ((_selectedUnit?['sell_price'] as num?)?.toDouble() ?? 0).toStringAsFixed(2);
        }
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Padding(
        padding: EdgeInsets.only(
          left: 16, right: 16, top: 8,
          bottom: MediaQuery.of(context).viewInsets.bottom + MediaQuery.of(context).padding.bottom + 16,
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40, height: 4,
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    color: AppColors.divider,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              Text('إضافة صنف', style: context.textTheme.titleLarge),
              const SizedBox(height: 16),

              // Search / barcode field
              TextField(
                controller: _searchController,
                decoration: InputDecoration(
                  hintText: 'بحث بالاسم أو الباركود...',
                  prefixIcon: const Icon(Icons.search),
                  suffixIcon: IconButton(
                    icon: const Icon(Icons.qr_code_scanner),
                    tooltip: 'مسح باركود',
                    onPressed: () async {
                      final result = await Navigator.push<String>(
                        context,
                        MaterialPageRoute(builder: (_) => const BarcodeScannerScreen()),
                      );
                      if (result != null && result.isNotEmpty) {
                        _searchController.text = result;
                        _searchProducts(result);
                      }
                    },
                  ),
                ),
                onChanged: (value) => _searchProducts(value),
              ),
              const SizedBox(height: 8),

              // Product search results
              Container(
                constraints: const BoxConstraints(maxHeight: 200),
                decoration: BoxDecoration(
                  border: Border.all(color: context.dividerColor),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: _isSearching
                    ? const Center(child: Padding(
                        padding: EdgeInsets.all(16),
                        child: CircularProgressIndicator(),
                      ))
                    : _searchResults.isEmpty
                        ? Center(child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Text('لا توجد نتائج', style: context.textTheme.bodyMedium),
                          ))
                        : ListView.builder(
                            shrinkWrap: true,
                            itemCount: _searchResults.length,
                            itemBuilder: (context, index) {
                              final product = _searchResults[index];
                              final isSelected = _selectedProduct?.id == product.id;
                              return ListTile(
                                dense: true,
                                selected: isSelected,
                                selectedTileColor: AppColors.primary.withValues(alpha: 0.08),
                                title: Text(product.nameAr, style: TextStyle(fontWeight: isSelected ? FontWeight.w700 : FontWeight.normal)),
                                subtitle: Text('${CurrencyFormatter.format(product.sellPrice)} | المخزون: ${product.currentStock.toStringAsFixed(0)}'),
                                trailing: isSelected
                                    ? const Icon(Icons.check_circle, color: AppColors.success, size: 20)
                                    : null,
                                onTap: () {
                                  setState(() {
                                    _selectedProduct = product;
                                    _searchController.text = product.nameAr;
                                    _availableUnits = [];
                                    _selectedUnit = null;
                                  });
                                  _loadUnitsForProduct(product.id!);
                                },
                              );
                            },
                          ),
              ),
              const SizedBox(height: 16),

              // Unit selection (if multiple units available)
              if (_selectedProduct != null && _availableUnits.length > 1) ...[
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.04),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: AppColors.primary.withValues(alpha: 0.12)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.straighten, size: 18, color: AppColors.primary),
                          const SizedBox(width: 6),
                          Text('اختر الوحدة', style: context.textTheme.titleSmall?.copyWith(color: AppColors.primary)),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: _availableUnits.map((unit) {
                          final isSelected = _selectedUnit?['unit_name'] == unit['unit_name'];
                          final factor = (unit['conversion_factor'] as num?)?.toDouble() ?? 1.0;
                          // Show cost_price for purchase invoices, sell_price for sale invoices
                          final price = widget.invoiceType == 'purchase'
                              ? (unit['cost_price'] as num?)?.toDouble() ?? 0.0
                              : (unit['sell_price'] as num?)?.toDouble() ?? 0.0;
                          return ChoiceChip(
                            label: Text('${unit['unit_name']} (${CurrencyFormatter.format(price)})'),
                            selected: isSelected,
                            onSelected: (_) {
                              setState(() {
                                _selectedUnit = unit;
                                _priceController.text = price.toStringAsFixed(2);
                              });
                            },
                            selectedColor: AppColors.primary.withValues(alpha: 0.12),
                          );
                        }).toList(),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
              ],

              // Loading units indicator
              if (_loadingUnits)
                const Padding(
                  padding: EdgeInsets.all(8),
                  child: Center(child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))),
                ),

              // Quantity & price row
              Row(
                children: [
                  Expanded(
                    child: _buildTextField(
                      label: 'الكمية${_unitName.isNotEmpty ? ' ($_unitName)' : ''}',
                      controller: _quantityController,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      onChanged: (_) => setState(() {}),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _buildTextField(
                      label: widget.invoiceType == 'purchase' ? 'سعر التكلفة${_unitName.isNotEmpty ? ' ($_unitName)' : ''}' : 'سعر البيع${_unitName.isNotEmpty ? ' ($_unitName)' : ''}',
                      controller: _priceController,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      suffixText: AppConstants.currency,
                      onChanged: (_) => setState(() {}),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),

              // Show base quantity info
              if (_selectedUnit != null && _conversionFactor != 1.0) ...[
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: AppColors.infoLight.withValues(alpha: 0.3),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.info_outline, size: 16, color: AppColors.info),
                      const SizedBox(width: 6),
                      Text(
                        'الكمية بالوحدة الأساسية: ${_baseQuantity.toStringAsFixed(2)}',
                        style: context.textTheme.bodySmall?.copyWith(color: AppColors.info),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
              ],

              _buildTextField(
                label: 'خصم على الصنف',
                controller: _discountController,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                suffixText: AppConstants.currency,
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: 12),

              _buildTextField(label: 'ملاحظات', controller: _notesController, maxLines: 2),
              const SizedBox(height: 16),

              // Total
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.06),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('الإجمالي', style: context.textTheme.titleSmall),
                    Text(CurrencyFormatter.format(_total),
                        style: context.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800, color: AppColors.primary)),
                  ],
                ),
              ),
              const SizedBox(height: 20),

              SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton(
                  onPressed: _addItem,
                  child: const Text('إضافة'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTextField({
    required String label,
    required TextEditingController controller,
    TextInputType? keyboardType,
    String? suffixText,
    int maxLines = 1,
    ValueChanged<String>? onChanged,
  }) {
    return TextField(
      controller: controller,
      keyboardType: keyboardType,
      maxLines: maxLines,
      onChanged: onChanged,
      decoration: InputDecoration(
        labelText: label,
        suffixText: suffixText,
      ),
    );
  }

  void _addItem() {
    if (_selectedProduct == null) {
      context.showErrorSnackBar('الرجاء اختيار المنتج');
      return;
    }
    if (_quantity <= 0) {
      context.showErrorSnackBar('الرجاء إدخال كمية صحيحة');
      return;
    }
    if (_unitPrice <= 0) {
      context.showErrorSnackBar('الرجاء إدخال سعر صحيح');
      return;
    }

    final item = InvoiceItem(
      invoiceId: '',
      productId: _selectedProduct!.id!,
      productName: _selectedProduct!.nameAr,
      quantity: _quantity,
      unitPrice: _unitPrice,
      totalPrice: _total,
      unitName: _unitName.isNotEmpty ? _unitName : null,
      conversionFactor: _conversionFactor,
      baseQuantity: _baseQuantity,
      notes: _notesController.text.isEmpty ? null : _notesController.text,
    );

    Navigator.pop(context, item);
  }
}
